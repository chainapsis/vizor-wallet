import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/enhance_pir_preference_store.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';

AppBootstrapState _ready({required bool? enabled, String network = 'main'}) =>
    AppBootstrapState(
      initialLocation: '/home',
      initialAccountState: const AccountState(),
      initialSyncSnapshot: AppSyncSnapshot.empty,
      network: network,
      rpcEndpointConfig: defaultRpcEndpointConfig(network),
      themeMode: ThemeMode.system,
      privacyModeEnabled: false,
      isPasswordConfigured: true,
      isUnlocked: true,
      passwordRotationRecoveryFailed: false,
      enhancePirEnabled: enabled,
    );

void main() {
  late List<String> applied;
  late bool failRaise;

  Future<void> apply(AppBootstrapState bootstrap) => applyEnhancePirPolicy(
    bootstrap,
    setRustEnabled: (enabled) => applied.add('rust:$enabled'),
    setPreferenceConfirmed: (confirmed) => applied.add('confirmed:$confirmed'),
    reconcileTransparentPolicy: (privateQueries) async {
      applied.add('reconcile:$privateQueries');
      if (failRaise) throw StateError('public lookups did not drain');
      return true;
    },
    setNativePrivateRecovery: (enabled) async => applied.add('native:$enabled'),
  );

  setUp(() {
    applied = [];
    failRaise = false;
  });

  // Masquerade builds never enable the production service.
  final available = isEnhancePirAvailableForNetwork('main');

  for (final kind in AppBootstrapFailureKind.values) {
    test(
      'a blocked bootstrap ($kind) leaves native private mode alone',
      () async {
        // The blocked state carries a default `false`, not the saved preference.
        final blocked = AppBootstrapState.blocked(
          failureKind: kind,
          failureMessage: 'blocked',
        );
        expect(blocked.enhancePirEnabled, isFalse);

        await apply(blocked);

        expect(applied, isEmpty, reason: 'nothing confirmed or reconciled');
      },
    );
  }

  test(
    'a saved preference is confirmed and raised before native is applied',
    () async {
      await apply(_ready(enabled: true));
      expect(applied, [
        'rust:$available',
        'confirmed:true',
        if (available) 'reconcile:true',
        'native:$available',
      ]);
    },
  );

  test('a failed raise keeps both sides private', () async {
    failRaise = true;
    await apply(_ready(enabled: true));
    expect(applied, [
      'rust:$available',
      'confirmed:true',
      if (available) 'reconcile:true',
      'native:$available',
    ]);
  });

  test(
    'an unreadable preference keeps both sides private, unconfirmed',
    () async {
      // What bootstrap builds when the saved preference cannot be read.
      final unreadable = await readEnhancePirEnabledPreference(
        _UnusedSecureStore(),
        preferences: _UnreadablePreferences(),
      );
      expect(unreadable, isNull);
      await apply(_ready(enabled: unreadable));
      expect(applied, [
        'rust:$available',
        'confirmed:false',
        'native:$available',
      ]);
      expect(applied, isNot(contains('native:false')));
    },
  );

  test('startup applies a disabled preference but never demotes', () async {
    await apply(_ready(enabled: false));
    // Only an explicit toggle-off lowers the transparent policy.
    expect(applied, ['rust:false', 'confirmed:true', 'native:false']);
  });

  test('a network without the service reconciles nothing', () async {
    await apply(_ready(enabled: true, network: 'test'));
    expect(applied, ['rust:false', 'confirmed:true', 'native:false']);
  });
}

class _UnreadablePreferences implements EnhancePirPreferenceStore {
  @override
  Future<bool?> readEnabled() async => throw StateError('read failed');

  @override
  Future<void> writeEnabled(bool enabled) async =>
      fail('an unknown preference must not be written');
}

/// Never reached: the failed preference read returns before the legacy lane.
class _UnusedSecureStore extends AppSecureStore {
  _UnusedSecureStore() : super.testing(storage: const FlutterSecureStorage());

  @override
  Future<String?> readPlain(String key) async =>
      fail('legacy flag read after a failed preference read');
}
