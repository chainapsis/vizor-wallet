import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/app_version_config.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/config/swap_remote_enable_config.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';

void main() {
  test('enables swap only for mainnet wallet networks', () {
    expect(isSwapFeatureEnabledForNetwork('main'), isTrue);
    expect(isSwapFeatureEnabledForNetwork('test'), isFalse);
    expect(isSwapFeatureEnabledForNetwork('regtest'), isFalse);
  });

  test('provider follows the bootstrapped wallet network', () {
    final cases = {'main': true, 'test': false, 'regtest': false};

    for (final entry in cases.entries) {
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            _bootstrap(network: entry.key),
          ),
          swapForceDisabledForCurrentBuildProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(swapFeatureEnabledProvider),
        entry.value,
        reason: 'network=${entry.key}',
      );
    }
  });

  group('parseSwapEnabledOverrideForVersion', () {
    test('requires an exact true value for the current version', () {
      expect(
        parseSwapEnabledOverrideForVersion('{"1.2.3":true}', '1.2.3'),
        true,
      );
      expect(
        parseSwapEnabledOverrideForVersion('{"1.2.3":false}', '1.2.3'),
        false,
      );
      expect(
        parseSwapEnabledOverrideForVersion('{"1.2.4":true}', '1.2.3'),
        false,
      );
      expect(
        parseSwapEnabledOverrideForVersion('{"1.2.3":"true"}', '1.2.3'),
        false,
      );
      expect(parseSwapEnabledOverrideForVersion('[]', '1.2.3'), false);
      expect(parseSwapEnabledOverrideForVersion('not json', '1.2.3'), false);
    });
  });

  group('shouldForceDisableSwapForCurrentBuild', () {
    test('only applies to explicitly forced iOS mobile builds', () {
      expect(
        shouldForceDisableSwapForCurrentBuild(
          forceDisableDefine: true,
          formFactor: AppFormFactor.mobile,
          isIOS: true,
        ),
        true,
      );
      expect(
        shouldForceDisableSwapForCurrentBuild(
          forceDisableDefine: false,
          formFactor: AppFormFactor.mobile,
          isIOS: true,
        ),
        false,
      );
      expect(
        shouldForceDisableSwapForCurrentBuild(
          forceDisableDefine: true,
          formFactor: AppFormFactor.desktop,
          isIOS: true,
        ),
        false,
      );
      expect(
        shouldForceDisableSwapForCurrentBuild(
          forceDisableDefine: true,
          formFactor: AppFormFactor.mobile,
          isIOS: false,
        ),
        false,
      );
    });
  });

  group('swapFeatureEnabledProvider', () {
    test('keeps current mainnet behavior when not force disabled', () async {
      final source = _FakeSwapEnabledOverrideSource(enabled: true);
      final container = _container(
        forceDisabled: false,
        source: source,
        store: _FakeSwapEnabledOverrideStore(),
      );
      final sub = container.listen(swapFeatureEnabledProvider, (_, _) {});

      expect(sub.read(), true);
      await _pumpAsync();
      expect(source.fetchCount, 0);
    });

    test('does not enable swap on non-mainnet networks', () async {
      final source = _FakeSwapEnabledOverrideSource(enabled: true);
      final container = _container(
        bootstrap: _bootstrap(network: 'test'),
        forceDisabled: true,
        source: source,
        store: _FakeSwapEnabledOverrideStore(),
      );
      final sub = container.listen(swapFeatureEnabledProvider, (_, _) {});

      expect(sub.read(), false);
      await _pumpAsync();
      expect(source.fetchCount, 0);
    });

    test('uses cached remote enablement immediately and skips fetch', () async {
      final source = _FakeSwapEnabledOverrideSource(enabled: true);
      final container = _container(
        bootstrap: _bootstrap(swapOverrideCached: true),
        forceDisabled: true,
        source: source,
        store: _FakeSwapEnabledOverrideStore(),
      );
      final sub = container.listen(swapFeatureEnabledProvider, (_, _) {});

      expect(sub.read(), true);
      await _pumpAsync();
      expect(source.fetchCount, 0);
    });

    test('stays disabled when remote override is missing or false', () async {
      final source = _FakeSwapEnabledOverrideSource(enabled: false);
      final store = _FakeSwapEnabledOverrideStore();
      final container = _container(
        forceDisabled: true,
        source: source,
        store: store,
      );
      final sub = container.listen(swapFeatureEnabledProvider, (_, _) {});

      expect(sub.read(), false);
      await _pumpAsync();

      expect(sub.read(), false);
      expect(source.fetchCount, 1);
      expect(store.cachedVersions, isEmpty);
    });

    test('remote true enables swap and caches the release version', () async {
      final source = _FakeSwapEnabledOverrideSource(enabled: true);
      final store = _FakeSwapEnabledOverrideStore();
      final container = _container(
        forceDisabled: true,
        source: source,
        store: store,
      );
      final sub = container.listen(swapFeatureEnabledProvider, (_, _) {});

      expect(sub.read(), false);
      await _pumpAsync();

      expect(sub.read(), true);
      expect(source.fetchCount, 1);
      expect(source.requestedVersions, [kVizorReleaseVersion]);
      expect(store.cachedVersions, [kVizorReleaseVersion]);
    });
  });

  group('SharedPreferencesSwapEnabledOverrideStore', () {
    test('stores the release override as a bool keyed by version', () async {
      SharedPreferences.setMockInitialValues({});
      const store = SharedPreferencesSwapEnabledOverrideStore();

      await store.cacheEnabledForVersion('9.9.9');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(swapEnabledOverrideStorageKey('9.9.9')), true);
    });
  });
}

ProviderContainer _container({
  AppBootstrapState? bootstrap,
  required bool forceDisabled,
  required _FakeSwapEnabledOverrideSource source,
  required _FakeSwapEnabledOverrideStore store,
}) {
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(bootstrap ?? _bootstrap()),
      swapForceDisabledForCurrentBuildProvider.overrideWithValue(forceDisabled),
      swapEnabledOverrideSourceProvider.overrideWithValue(source),
      swapEnabledOverrideStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AppBootstrapState _bootstrap({
  String network = 'main',
  bool swapOverrideCached = false,
}) {
  return AppBootstrapState(
    initialLocation: '/welcome',
    initialAccountState: AccountState(),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: network,
    rpcEndpointConfig: defaultRpcEndpointConfig(network),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    swapEnabledOverrideCachedForRelease: swapOverrideCached,
    isPasswordConfigured: false,
    isUnlocked: false,
    passwordRotationRecoveryFailed: false,
  );
}

Future<void> _pumpAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeSwapEnabledOverrideSource implements SwapEnabledOverrideSource {
  _FakeSwapEnabledOverrideSource({required this.enabled});

  final bool enabled;
  var fetchCount = 0;
  final requestedVersions = <String>[];

  @override
  Future<bool> isEnabledForVersion(String version) async {
    fetchCount++;
    requestedVersions.add(version);
    return enabled;
  }
}

class _FakeSwapEnabledOverrideStore implements SwapEnabledOverrideStore {
  final cachedVersions = <String>[];

  @override
  Future<void> cacheEnabledForVersion(String version) async {
    cachedVersions.add(version);
  }
}
