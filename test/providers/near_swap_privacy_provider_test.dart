import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/storage/enhance_pir_preference_store.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

class _Api extends RustLibApi {
  final events = <String>[];
  @override
  void crateApiSyncSetNearSwapPrivacyEnabled({required bool enabled}) =>
      events.add('swap:$enabled');
  @override
  void crateApiSyncSetEnhancePirEnabled({required bool enabled}) =>
      events.add('private:$enabled');
  @override
  void crateApiSyncSetEnhancePirPreferenceConfirmed({
    required bool confirmed,
  }) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync extends SyncNotifier {
  final gate = Completer<void>();
  int starts = 0;
  int swapRecoveryRequests = 0;
  @override
  Future<SyncState> build() async => SyncState();
  @override
  void requestSwapRecovery() => swapRecoveryRequests++;
  // A changed transparent policy restarts sync; these tests have no wallet.
  @override
  void startSync({int? latestTipHeight}) => starts++;
  @override
  Future<void> withRecoverySettingPaused(Future<void> Function() action) async {
    await gate.future;
    await action();
  }
}

/// The private queries opt-out marker, which turning private queries off writes
/// before anything weakens.
class _OptOut implements TransparentOptOutStore {
  bool value = false;
  @override
  Future<bool> readPending() async => value;
  @override
  Future<void> writePending(bool pending) async => value = pending;
}

/// Lowers or raises the wallet's transparent policy as the setting asks.
Future<ApiAppliedTransparentPolicy?> _reconcile(bool privateQueries) async =>
    ApiAppliedTransparentPolicy(
      mode: privateQueries
          ? ApiTransparentLedgerMode.privateRequired
          : ApiTransparentLedgerMode.public,
      generation: BigInt.one,
    );

class _Store implements EnhancePirPreferenceStore {
  bool? value;
  bool fail = false;

  /// Holds writes until completed, when set.
  Completer<void>? gate;
  @override
  Future<bool?> readEnabled() async => value;
  @override
  Future<void> writeEnabled(bool enabled) async {
    await gate?.future;
    if (fail) throw StateError('disk unavailable');
    value = enabled;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(() => api.events.clear());
  ProviderContainer setup(
    _Store store,
    _Sync sync, {
    bool private = false,
    bool swap = false,
    String network = 'main',
    List<Override> extra = const [],
  }) {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          AppBootstrapState(
            initialLocation: '/settings',
            initialAccountState: const AccountState(),
            initialSyncSnapshot: AppSyncSnapshot.empty,
            network: network,
            rpcEndpointConfig: defaultRpcEndpointConfig(network),
            themeMode: ThemeMode.system,
            privacyModeEnabled: false,
            isPasswordConfigured: false,
            isUnlocked: true,
            passwordRotationRecoveryFailed: false,
            enhancePirEnabled: private,
            nearSwapPrivacyEnabled: swap,
          ),
        ),
        syncProvider.overrideWith(() => sync),
        nearSwapPrivacyPreferenceStoreProvider.overrideWithValue(store),
        enhancePirPreferenceStoreProvider.overrideWithValue(_Store()),
        enhancePirBackgroundSinkProvider.overrideWithValue((_) async {}),
        transparentOptOutStoreProvider.overrideWithValue(_OptOut()),
        transparentPolicyReconcilerProvider.overrideWithValue(_reconcile),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('defaults off and turns on without Private queries', () async {
    final store = _Store();
    final c = setup(store, _Sync());
    expect(c.read(nearSwapPrivacyProvider), isFalse);
    await c.read(nearSwapPrivacyProvider.notifier).set(true);
    expect(c.read(nearSwapPrivacyProvider), isTrue);
    expect(store.value, isTrue);
    expect(api.events, ['swap:true']);
  });
  test(
    'saves and applies the opt-in without pausing or starting sync',
    () async {
      final store = _Store();
      // A pause would wait on this gate, which never opens.
      final sync = _Sync();
      final c = setup(store, sync, private: true);
      await c.read(nearSwapPrivacyProvider.notifier).set(true);
      expect(store.value, isTrue);
      expect(c.read(nearSwapPrivacyProvider), isTrue);
      expect(api.events, ['swap:true']);
      expect(sync.starts, 0);
    },
  );
  test(
    'turning it on requests a swap recovery round, and off does not',
    () async {
      final sync = _Sync();
      final c = setup(_Store(), sync);
      await c.read(nearSwapPrivacyProvider.notifier).set(true);
      expect(sync.swapRecoveryRequests, 1);
      await c.read(nearSwapPrivacyProvider.notifier).set(false);
      expect(sync.swapRecoveryRequests, 1);
    },
  );
  test('turning Private queries off leaves the opt-in alone', () async {
    final store = _Store()..value = true;
    final c = setup(store, _Sync()..gate.complete(), private: true, swap: true);
    await c.read(enhancePirProvider.notifier).set(false);
    expect(c.read(enhancePirProvider), isFalse);
    expect(store.value, isTrue);
    expect(c.read(nearSwapPrivacyProvider), isTrue);
    expect(api.events, ['private:false']);
  });
  test('failed enable does not issue addresses', () async {
    final store = _Store()..fail = true;
    final c = setup(store, _Sync(), private: true);
    await c.read(nearSwapPrivacyProvider.notifier).set(true);
    expect(c.read(nearSwapPrivacyProvider), isFalse);
    expect(api.events, isEmpty);
  });
  test('turning the setting off does not sync', () async {
    final store = _Store()..value = true;
    final sync = _Sync();
    final c = setup(store, sync, private: true, swap: true);
    await c.read(nearSwapPrivacyProvider.notifier).set(false);
    expect(c.read(nearSwapPrivacyProvider), isFalse);
    expect(store.value, isFalse);
    expect(api.events, ['swap:false']);
    expect(sync.starts, 0);
  });
  test('its feedback stays off the Private queries row', () async {
    final store = _Store()..gate = Completer<void>();
    final c = setup(store, _Sync(), private: true);
    final change = c.read(nearSwapPrivacyProvider.notifier).set(true);
    expect(
      c.read(nearSwapPrivacyTransitionProvider),
      kEnhancePirChangingMessage,
    );
    expect(c.read(enhancePirTransitionProvider), isNull);
    store.gate!.complete();
    await change;
    expect(c.read(nearSwapPrivacyTransitionProvider), isNull);
    expect(c.read(enhancePirTransitionProvider), isNull);
  });
  test('a failed change says so under its own row', () async {
    final store = _Store()..fail = true;
    final c = setup(store, _Sync(), private: true);
    await c.read(nearSwapPrivacyProvider.notifier).set(true);
    expect(
      c.read(nearSwapPrivacyTransitionProvider),
      kEnhancePirUnchangedMessage,
    );
    expect(c.read(enhancePirTransitionProvider), isNull);
  });
  test('a restart with the opt-in on and Private queries off keeps it on', () {
    final c = setup(_Store(), _Sync(), swap: true);
    expect(c.read(enhancePirProvider), isFalse);
    expect(c.read(nearSwapPrivacyProvider), isTrue);
    final off = setup(_Store(), _Sync(), private: true);
    expect(off.read(nearSwapPrivacyProvider), isFalse);
  });

  /// Settings offers the row only where the private service runs, so swaps
  /// alone don't show it.
  test('the row stays hidden while the private service is off', () {
    final c = setup(
      _Store(),
      _Sync(),
      swap: true,
      extra: [
        swapFeatureEnabledProvider.overrideWithValue(true),
        enhancePirAvailableProvider.overrideWithValue(false),
      ],
    );
    expect(c.read(nearSwapPrivacySettingAvailableProvider), isFalse);
    expect(c.read(nearSwapPrivacyProvider), isFalse);
  });

  /// Off mainnet there are no swaps and no private service, so a saved opt-in
  /// neither shows the row nor turns the feature on.
  test('testnet hides the row and keeps a saved opt-in off', () {
    final c = setup(
      _Store(),
      _Sync(),
      private: true,
      swap: true,
      network: 'test',
    );
    expect(c.read(nearSwapPrivacySettingAvailableProvider), isFalse);
    expect(c.read(nearSwapPrivacyProvider), isFalse);
  });
  test(
    'the install preference defaults off and survives store recreation',
    () async {
      SharedPreferences.setMockInitialValues({});
      expect(await readNearSwapPrivacyPreference(), isFalse);
      await const SharedPreferencesEnhancePirStore(
        key: kNearSwapPrivacyPreferenceKey,
      ).writeEnabled(true);
      expect(await readNearSwapPrivacyPreference(), isTrue);
      expect(
        await const SharedPreferencesEnhancePirStore().readEnabled(),
        isNull,
      );
    },
  );
}
