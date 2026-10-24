import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
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
  @override
  Future<SyncState> build() async => SyncState();
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
  @override
  Future<bool?> readEnabled() async => value;
  @override
  Future<void> writeEnabled(bool enabled) async {
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
    bool failReconcile = false,
  }) {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          AppBootstrapState(
            initialLocation: '/settings',
            initialAccountState: const AccountState(),
            initialSyncSnapshot: AppSyncSnapshot.empty,
            network: 'main',
            rpcEndpointConfig: defaultRpcEndpointConfig('main'),
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
        swapRecoveryReconcilerProvider.overrideWithValue(() async {
          if (failReconcile) throw StateError('wallet unavailable');
        }),
        nearSwapPrivacyPreferenceStoreProvider.overrideWithValue(store),
        enhancePirPreferenceStoreProvider.overrideWithValue(_Store()),
        enhancePirBackgroundSinkProvider.overrideWithValue((_) async {}),
        transparentOptOutStoreProvider.overrideWithValue(_OptOut()),
        transparentPolicyReconcilerProvider.overrideWithValue(_reconcile),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('defaults off and cannot enable without Private queries', () async {
    final store = _Store();
    final c = setup(store, _Sync()..gate.complete());
    expect(c.read(nearSwapPrivacyProvider), isFalse);
    await c.read(nearSwapPrivacyProvider.notifier).set(true);
    expect(c.read(nearSwapPrivacyProvider), isFalse);
    expect(store.value, isNull);
    expect(api.events, isEmpty);
  });
  test('pauses work before persisting and applying the opt-in', () async {
    final store = _Store();
    final sync = _Sync();
    final c = setup(store, sync, private: true);
    final pending = c.read(nearSwapPrivacyProvider.notifier).set(true);
    await Future<void>.delayed(Duration.zero);
    expect(store.value, isNull);
    expect(api.events, isEmpty);
    sync.gate.complete();
    await pending;
    expect(store.value, isTrue);
    expect(c.read(nearSwapPrivacyProvider), isTrue);
    // Reconciliation does not start an ordinary block sync.
    expect(api.events, ['swap:true']);
    expect(sync.starts, 0);
  });
  test('turning off Private queries durably clears the child first', () async {
    final store = _Store()..value = true;
    final c = setup(store, _Sync()..gate.complete(), private: true, swap: true);
    await c.read(enhancePirProvider.notifier).set(false);
    expect(store.value, isFalse);
    expect(c.read(nearSwapPrivacyProvider), isFalse);
    expect(api.events, ['swap:false', 'private:false']);
    await c.read(enhancePirProvider.notifier).set(true);
    expect(c.read(nearSwapPrivacyProvider), isFalse);
  });
  test('failed child write preserves both settings and runtime', () async {
    final store = _Store()
      ..value = true
      ..fail = true;
    final c = setup(store, _Sync()..gate.complete(), private: true, swap: true);
    await c.read(enhancePirProvider.notifier).set(false);
    expect(c.read(enhancePirProvider), isTrue);
    expect(c.read(nearSwapPrivacyProvider), isTrue);
    expect(api.events, isEmpty);
  });
  test('failed enable does not issue addresses', () async {
    final store = _Store()..fail = true;
    final c = setup(store, _Sync()..gate.complete(), private: true);
    await c.read(nearSwapPrivacyProvider.notifier).set(true);
    expect(c.read(nearSwapPrivacyProvider), isFalse);
    expect(api.events, isEmpty);
  });
  test('turning the setting off does not sync', () async {
    final store = _Store()..value = true;
    final sync = _Sync()..gate.complete();
    final c = setup(store, sync, private: true, swap: true);
    await c.read(nearSwapPrivacyProvider.notifier).set(false);
    expect(c.read(nearSwapPrivacyProvider), isFalse);
    expect(api.events, ['swap:false']);
    expect(sync.starts, 0);
  });
  test('reconcile failure keeps the saved opt-in visible', () async {
    final store = _Store();
    final c = setup(
      store,
      _Sync()..gate.complete(),
      private: true,
      failReconcile: true,
    );
    await c.read(nearSwapPrivacyProvider.notifier).set(true);
    expect(store.value, isTrue);
    expect(c.read(nearSwapPrivacyProvider), isTrue);
    expect(api.events, ['swap:true']);
    expect(
      c.read(nearSwapPrivacyTransitionProvider),
      kSwapRecoveryPendingMessage,
    );
    expect(c.read(enhancePirTransitionProvider), isNull);
    expect(c.read(privateQueriesTransitionProvider), isNull);
  });
  test('its feedback stays off the Private queries row', () async {
    final sync = _Sync();
    final c = setup(_Store(), sync, private: true);
    final change = c.read(nearSwapPrivacyProvider.notifier).set(true);
    // Other setting changes still wait for this one.
    expect(c.read(enhancePirTransitionProvider), kEnhancePirChangingMessage);
    expect(
      c.read(nearSwapPrivacyTransitionProvider),
      kEnhancePirChangingMessage,
    );
    expect(c.read(privateQueriesTransitionProvider), isNull);
    sync.gate.complete();
    await change;
    expect(c.read(enhancePirTransitionProvider), isNull);
    expect(c.read(nearSwapPrivacyTransitionProvider), isNull);
  });
  test('a failed change says so under its own row', () async {
    final store = _Store()..fail = true;
    final c = setup(store, _Sync()..gate.complete(), private: true);
    await c.read(nearSwapPrivacyProvider.notifier).set(true);
    expect(
      c.read(nearSwapPrivacyTransitionProvider),
      kEnhancePirUnchangedMessage,
    );
    expect(c.read(privateQueriesTransitionProvider), isNull);
  });
  test('changing Private queries clears its old feedback', () async {
    final c = setup(
      _Store(),
      _Sync()..gate.complete(),
      private: true,
      failReconcile: true,
    );
    await c.read(nearSwapPrivacyProvider.notifier).set(true);
    expect(
      c.read(nearSwapPrivacyTransitionProvider),
      kSwapRecoveryPendingMessage,
    );
    await c.read(enhancePirProvider.notifier).set(false);
    expect(c.read(nearSwapPrivacyProvider), isFalse);
    expect(c.read(nearSwapPrivacyTransitionProvider), isNull);
  });
  test(
    'reconcile failure does not leave an enabled child under an off parent',
    () async {
      final store = _Store()..value = true;
      final c = setup(
        store,
        _Sync()..gate.complete(),
        private: true,
        swap: true,
        failReconcile: true,
      );
      await c.read(enhancePirProvider.notifier).set(false);
      expect(store.value, isFalse);
      expect(c.read(nearSwapPrivacyProvider), isFalse);
      expect(c.read(enhancePirProvider), isFalse);
      expect(api.events, ['swap:false', 'private:false']);
    },
  );
  test('saved opt-in requires its saved parent at bootstrap', () {
    final c = setup(_Store(), _Sync(), swap: true);
    expect(c.read(nearSwapPrivacyProvider), isFalse);
    final restored = setup(_Store(), _Sync(), private: true, swap: true);
    expect(restored.read(nearSwapPrivacyProvider), isTrue);
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
