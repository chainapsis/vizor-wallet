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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync extends SyncNotifier {
  final gate = Completer<void>();
  @override
  Future<SyncState> build() async => SyncState();
  @override
  Future<void> withRecoverySettingPaused(Future<void> Function() action) async {
    await gate.future;
    await action();
  }
}

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
        nearSwapPrivacyPreferenceStoreProvider.overrideWithValue(store),
        enhancePirPreferenceStoreProvider.overrideWithValue(_Store()),
        enhancePirBackgroundSinkProvider.overrideWithValue((_) async {}),
        swapHistoryRecheckProvider.overrideWithValue(
          () async => api.events.add('recheck'),
        ),
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
    // Turning the setting on rechecks closed swap keys once.
    expect(api.events, ['swap:true', 'recheck']);
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
