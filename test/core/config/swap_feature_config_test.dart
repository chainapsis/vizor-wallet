import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/app_version_config.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/config/swap_remote_enable_config.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/layout/app_process_work_policy.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';

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

    // The launch fetch of a Tor wallet is refused in milliseconds by a route
    // that is still bootstrapping. Nothing else asks again, so without this
    // swap stays off for the whole session.
    test('an unresolved fetch is re-asked once the route settles', () async {
      final source = _FakeSwapEnabledOverrideSource(
        enabled: true,
        unresolvedCalls: 1,
      );
      final store = _FakeSwapEnabledOverrideStore();
      final privacy = _FakeNetworkPrivacyNotifier();
      final container = _container(
        forceDisabled: true,
        source: source,
        store: store,
        privacy: privacy,
      );
      final sub = container.listen(swapFeatureEnabledProvider, (_, _) {});

      expect(sub.read(), false);
      await _pumpAsync();
      expect(source.fetchCount, 1);
      expect(sub.read(), false);
      expect(store.cachedVersions, isEmpty);

      privacy.publish(_privacyState(NetworkPrivacyConnectionStatus.connected));
      await _pumpAsync();

      expect(source.fetchCount, 2);
      expect(sub.read(), true);
      expect(store.cachedVersions, [kVizorReleaseVersion]);
    });

    test('a definitive false is never re-asked', () async {
      final source = _FakeSwapEnabledOverrideSource(enabled: false);
      final store = _FakeSwapEnabledOverrideStore();
      final privacy = _FakeNetworkPrivacyNotifier();
      final container = _container(
        forceDisabled: true,
        source: source,
        store: store,
        privacy: privacy,
      );
      final sub = container.listen(swapFeatureEnabledProvider, (_, _) {});

      await _pumpAsync();
      expect(source.fetchCount, 1);

      privacy.publish(_privacyState(NetworkPrivacyConnectionStatus.connected));
      await _pumpAsync();

      expect(source.fetchCount, 1);
      expect(sub.read(), false);
      expect(store.cachedVersions, isEmpty);
    });

    test('a route change during a fetch does not start a second one', () async {
      final source = _FakeSwapEnabledOverrideSource(
        enabled: true,
        unresolvedCalls: 1,
        holdCall: 2,
      );
      final store = _FakeSwapEnabledOverrideStore();
      final privacy = _FakeNetworkPrivacyNotifier();
      final container = _container(
        forceDisabled: true,
        source: source,
        store: store,
        privacy: privacy,
      );
      final sub = container.listen(swapFeatureEnabledProvider, (_, _) {});

      await _pumpAsync();
      expect(source.fetchCount, 1);

      // Arms the retry, then parks the retry fetch in flight.
      privacy.publish(_privacyState(NetworkPrivacyConnectionStatus.off));
      await _pumpAsync();
      expect(source.fetchCount, 2);

      privacy.publish(_privacyState(NetworkPrivacyConnectionStatus.connected));
      await _pumpAsync();

      expect(source.fetchCount, 2);
      expect(sub.read(), false);
    });

    test('an unresolved fetch stays disabled without a route change', () async {
      final source = _FakeSwapEnabledOverrideSource(
        enabled: true,
        unresolvedCalls: 1,
      );
      final store = _FakeSwapEnabledOverrideStore();
      final privacy = _FakeNetworkPrivacyNotifier();
      final container = _container(
        forceDisabled: true,
        source: source,
        store: store,
        privacy: privacy,
      );
      final sub = container.listen(swapFeatureEnabledProvider, (_, _) {});

      await _pumpAsync();
      // A repeat of the same connecting status is not a settled route.
      privacy.publish(_privacyState(NetworkPrivacyConnectionStatus.connecting));
      await _pumpAsync();

      expect(source.fetchCount, 1);
      expect(sub.read(), false);
      expect(store.cachedVersions, isEmpty);
    });
  });

  // `testWidgets` runs its body inside `FakeAsync`, so `tester.pump(duration)`
  // is virtual time: retry timers fire exactly on schedule with no real
  // waiting, and a timer still pending when the test ends fails it.
  group('unresolved fetch retries in the background', () {
    bool mobilePolicy({required bool isInForeground}) => canRunAppProcessWork(
      isInForeground: isInForeground,
      formFactor: AppFormFactor.mobile,
    );

    void lifecycle(AppLifecycleState state) {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);
    }

    // The listener asserts the platform's legal transitions, so a return to
    // the foreground has to climb back the way it left.
    void background() {
      lifecycle(AppLifecycleState.inactive);
      lifecycle(AppLifecycleState.hidden);
      lifecycle(AppLifecycleState.paused);
    }

    void foreground() {
      lifecycle(AppLifecycleState.hidden);
      lifecycle(AppLifecycleState.inactive);
      lifecycle(AppLifecycleState.resumed);
    }

    testWidgets(
      'mobile parks a pending retry on hide and settles it on resume',
      (tester) async {
        final source = _FakeSwapEnabledOverrideSource(
          enabled: true,
          unresolvedCalls: 1,
        );
        final store = _FakeSwapEnabledOverrideStore();
        final container = _container(
          source: source,
          store: store,
          forceDisabled: true,
          processWorkPolicy: mobilePolicy,
        );
        addTearDown(container.dispose);
        final sub = container.listen(
          swapEnabledRemoteOverrideProvider,
          (_, _) {},
        );
        await tester.pump();
        expect(source.fetchCount, 1);

        background();
        await tester.pump(const Duration(minutes: 10));
        expect(source.fetchCount, 1, reason: 'no retry while backgrounded');
        expect(sub.read(), false);

        foreground();
        await tester.pump();
        expect(source.fetchCount, 2, reason: 'the owed retry runs on resume');
        expect(sub.read(), true);
        expect(store.cachedVersions, [kVizorReleaseVersion]);
        await tester.pump(const Duration(minutes: 10));
        expect(source.fetchCount, 2);
      },
    );

    testWidgets('mobile arms nothing for a failure that lands while hidden', (
      tester,
    ) async {
      final source = _FakeSwapEnabledOverrideSource(
        enabled: true,
        unresolvedCalls: 1,
        holdCall: 1,
      );
      final store = _FakeSwapEnabledOverrideStore();
      final container = _container(
        source: source,
        store: store,
        forceDisabled: true,
        processWorkPolicy: mobilePolicy,
      );
      addTearDown(container.dispose);
      container.listen(swapEnabledRemoteOverrideProvider, (_, _) {});
      await tester.pump();
      expect(source.fetchCount, 1);

      background();
      source.releaseHeldCall();
      await tester.pump();
      await tester.pump(const Duration(minutes: 10));
      expect(source.fetchCount, 1, reason: 'the failure must not arm a timer');

      foreground();
      await tester.pump();
      expect(source.fetchCount, 2);
    });

    testWidgets('mobile defers a route-change retry until resume', (
      tester,
    ) async {
      final source = _FakeSwapEnabledOverrideSource(
        enabled: true,
        unresolvedCalls: 1,
      );
      final store = _FakeSwapEnabledOverrideStore();
      final privacy = _FakeNetworkPrivacyNotifier();
      final container = _container(
        source: source,
        store: store,
        forceDisabled: true,
        privacy: privacy,
        processWorkPolicy: mobilePolicy,
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        swapEnabledRemoteOverrideProvider,
        (_, _) {},
      );
      await tester.pump();
      expect(source.fetchCount, 1);

      background();
      privacy.publish(_privacyState(NetworkPrivacyConnectionStatus.connected));
      await tester.pump();
      await tester.pump(const Duration(minutes: 10));
      expect(source.fetchCount, 1, reason: 'no request while backgrounded');

      foreground();
      await tester.pump();
      expect(source.fetchCount, 2);
      expect(sub.read(), true);
    });

    testWidgets('desktop keeps retrying with its windows hidden', (
      tester,
    ) async {
      final source = _FakeSwapEnabledOverrideSource(
        enabled: true,
        unresolvedCalls: 1,
      );
      final container = _container(
        source: source,
        store: _FakeSwapEnabledOverrideStore(),
        forceDisabled: true,
        processWorkPolicy: ({required bool isInForeground}) =>
            canRunAppProcessWork(
              isInForeground: isInForeground,
              formFactor: AppFormFactor.desktop,
            ),
      );
      addTearDown(container.dispose);
      container.listen(swapEnabledRemoteOverrideProvider, (_, _) {});
      await tester.pump();

      background();
      await tester.pump(const Duration(seconds: 15));
      expect(source.fetchCount, 2, reason: 'desktop is not foreground-only');
      foreground();
      await tester.pump();
    });
  });

  group('unresolved fetch retries', () {
    testWidgets('re-asks on a timer when no route change comes', (
      tester,
    ) async {
      final source = _FakeSwapEnabledOverrideSource(
        enabled: true,
        unresolvedCalls: 1,
      );
      final store = _FakeSwapEnabledOverrideStore();
      final container = _container(
        forceDisabled: true,
        source: source,
        store: store,
      );
      final sub = container.listen(swapFeatureEnabledProvider, (_, _) {});

      await tester.pump();
      expect(source.fetchCount, 1);
      expect(sub.read(), false);

      await tester.pump(const Duration(seconds: 14));
      expect(source.fetchCount, 1);

      await tester.pump(const Duration(seconds: 1));
      expect(source.fetchCount, 2);
      expect(sub.read(), true);
      expect(store.cachedVersions, [kVizorReleaseVersion]);
    });

    testWidgets('each unresolved attempt waits longer than the last', (
      tester,
    ) async {
      final source = _FakeSwapEnabledOverrideSource(
        enabled: true,
        unresolvedCalls: 2,
      );
      final store = _FakeSwapEnabledOverrideStore();
      final container = _container(
        forceDisabled: true,
        source: source,
        store: store,
      );
      final sub = container.listen(swapFeatureEnabledProvider, (_, _) {});

      await tester.pump();
      expect(source.fetchCount, 1);

      await tester.pump(const Duration(seconds: 15));
      expect(source.fetchCount, 2);

      // The second wait is 30s, not another 15s.
      await tester.pump(const Duration(seconds: 29));
      expect(source.fetchCount, 2);

      await tester.pump(const Duration(seconds: 1));
      expect(source.fetchCount, 3);
      expect(sub.read(), true);
      expect(store.cachedVersions, [kVizorReleaseVersion]);

      // An answered fetch owes nothing further: no attempt over the next ten
      // minutes, and no timer left pending for the binding to complain about.
      await tester.pump(const Duration(minutes: 10));
      expect(source.fetchCount, 3);
    });

    testWidgets('a definitive false schedules nothing', (tester) async {
      final source = _FakeSwapEnabledOverrideSource(enabled: false);
      final store = _FakeSwapEnabledOverrideStore();
      final container = _container(
        forceDisabled: true,
        source: source,
        store: store,
      );
      final sub = container.listen(swapFeatureEnabledProvider, (_, _) {});

      await tester.pump();
      expect(source.fetchCount, 1);

      await tester.pump(const Duration(minutes: 10));
      expect(source.fetchCount, 1);
      expect(sub.read(), false);
      expect(store.cachedVersions, isEmpty);
    });

    testWidgets('a route change takes over the pending attempt', (
      tester,
    ) async {
      final source = _FakeSwapEnabledOverrideSource(
        enabled: true,
        unresolvedCalls: 1,
      );
      final store = _FakeSwapEnabledOverrideStore();
      final privacy = _FakeNetworkPrivacyNotifier();
      final container = _container(
        forceDisabled: true,
        source: source,
        store: store,
        privacy: privacy,
      );
      final sub = container.listen(swapFeatureEnabledProvider, (_, _) {});

      await tester.pump();
      expect(source.fetchCount, 1);

      await tester.pump(const Duration(seconds: 5));
      privacy.publish(_privacyState(NetworkPrivacyConnectionStatus.connected));
      await tester.pump();

      expect(source.fetchCount, 2);
      expect(sub.read(), true);

      // The timer the route change took over must not fire a duplicate.
      await tester.pump(const Duration(seconds: 30));
      expect(source.fetchCount, 2);
    });

    testWidgets('disposing the provider cancels the pending attempt', (
      tester,
    ) async {
      final source = _FakeSwapEnabledOverrideSource(
        enabled: true,
        unresolvedCalls: 1,
      );
      final container = _container(
        forceDisabled: true,
        source: source,
        store: _FakeSwapEnabledOverrideStore(),
        autoDispose: false,
      );
      container.listen(swapFeatureEnabledProvider, (_, _) {});

      await tester.pump();
      expect(source.fetchCount, 1);

      container.dispose();
      await tester.pump(const Duration(minutes: 10));

      expect(source.fetchCount, 1);
    });
  });

  group('HttpSwapEnabledOverrideSource', () {
    test('answers false only from a document it actually read', () async {
      Future<bool> ask(TorHttpBridge bridge) {
        final source = HttpSwapEnabledOverrideSource(
          networkClient: NetworkHttpClient(
            torDesired: () => true,
            torBootstrapping: () => false,
            torBridge: bridge,
          ),
          endpoint: Uri.parse('https://example.com/swap.json'),
        );
        addTearDown(source.close);
        return source.isEnabledForVersion('1.2.3');
      }

      // Read: the version is simply not enabled in the document.
      expect(await ask(const _StubTorBridge(200, '{"1.2.4":true}')), false);
      expect(await ask(const _StubTorBridge(200, '{"1.2.3":true}')), true);

      // Never read: a fail-closed route refuses the request outright, and a
      // server error says nothing about this version either.
      await expectLater(ask(const _StubTorBridge.failing()), throwsA(anything));
      await expectLater(ask(const _StubTorBridge(503, '')), throwsA(anything));
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
  _FakeNetworkPrivacyNotifier? privacy,
  bool autoDispose = true,
  bool Function({required bool isInForeground})? processWorkPolicy,
}) {
  final privacyNotifier = privacy ?? _FakeNetworkPrivacyNotifier();
  final container = ProviderContainer(
    overrides: [
      if (processWorkPolicy != null)
        swapOverrideProcessWorkPolicyProvider.overrideWithValue(
          processWorkPolicy,
        ),
      appBootstrapProvider.overrideWithValue(bootstrap ?? _bootstrap()),
      swapForceDisabledForCurrentBuildProvider.overrideWithValue(forceDisabled),
      swapEnabledOverrideSourceProvider.overrideWithValue(source),
      swapEnabledOverrideStoreProvider.overrideWithValue(store),
      networkPrivacyProvider.overrideWith(() => privacyNotifier),
    ],
  );
  if (autoDispose) addTearDown(container.dispose);
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

class _StubTorBridge implements TorHttpBridge {
  const _StubTorBridge(this.statusCode, this.body) : _fails = false;
  const _StubTorBridge.failing() : statusCode = 0, body = '', _fails = true;

  final int statusCode;
  final String body;
  final bool _fails;

  NetworkHttpResponse _response() {
    if (_fails) throw StateError('Tor is still connecting');
    return NetworkHttpResponse(
      statusCode: statusCode,
      bodyBytes: utf8.encode(body),
    );
  }

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration? timeout,
    Future<void>? cancelSignal,
  }) async => _response();

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
    required Duration? timeout,
    Future<void>? cancelSignal,
  }) async => _response();

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) async => _response();
}

NetworkPrivacyState _privacyState(NetworkPrivacyConnectionStatus status) =>
    NetworkPrivacyState(torEnabled: true, status: status);

/// Publishes route states on demand. Starts connecting, the state a Tor launch
/// is in while the first override fetch is refused.
class _FakeNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() =>
      _privacyState(NetworkPrivacyConnectionStatus.connecting);

  void publish(NetworkPrivacyState next) {
    state = next;
  }
}

class _FakeSwapEnabledOverrideSource implements SwapEnabledOverrideSource {
  _FakeSwapEnabledOverrideSource({
    required this.enabled,
    this.unresolvedCalls = 0,
    this.holdCall,
  });

  final bool enabled;

  /// How many leading calls leave the answer unknown by throwing — the shape
  /// of a request refused by a fail-closed route.
  final int unresolvedCalls;

  /// 1-based call index that never completes, so a test can hold one fetch in
  /// flight while the route changes again.
  final int? holdCall;

  final _held = Completer<void>();

  void releaseHeldCall() {
    if (!_held.isCompleted) _held.complete();
  }

  var fetchCount = 0;
  final requestedVersions = <String>[];

  @override
  Future<bool> isEnabledForVersion(String version) async {
    fetchCount++;
    requestedVersions.add(version);
    final call = fetchCount;
    // Held first, so a held call can still end unresolved once released —
    // the shape of a request that fails after the app has left the
    // foreground.
    if (call == holdCall) await _held.future;
    if (call <= unresolvedCalls) {
      throw StateError('Tor is still connecting');
    }
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
