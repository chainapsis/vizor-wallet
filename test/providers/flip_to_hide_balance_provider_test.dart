import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/flip_to_hide_balance_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

class _NoDatabaseRustApi implements RustLibApi {
  @override
  bool crateApiWalletWalletExists({required String dbPath}) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.initMock(api: _NoDatabaseRustApi()));
  tearDownAll(RustLib.dispose);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      kWalletDbNameKey: 'zcash_wallet_flip_test.db',
    });
    AppSecureStore.instance.clearSessionPassword();
    final support = await Directory.systemTemp.createTemp('vizor-flip-boot-');
    addTearDown(() => support.delete(recursive: true));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => support.path);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  Future<ProviderContainer> restart() async {
    final bootstrap = await loadAppBootstrap();
    expect(bootstrap.hasBlockingFailure, isFalse);
    final container = ProviderContainer(
      overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('empty bootstrap defaults to flip opt-out', () {
    expect(AppBootstrapState.empty.flipToHideBalanceEnabled, isFalse);
  });

  for (final existingWallet in [false, true]) {
    test(
      '${existingWallet ? 'upgrades' : 'new installs'} start with flip off',
      () async {
        if (existingWallet) {
          const account = AccountInfo(
            uuid: 'fixture',
            name: 'Fixture',
            order: 0,
          );
          final store = AppSecureStore.instance;
          await store.writePlain(
            'zcash_accounts',
            jsonEncode([account.toJson()]),
          );
          await store.writePlain('zcash_active_account', account.uuid);
          await store.writePlain('zcash_password_verifier', 'verifier');
          await store.writePlain('zcash_password_verifier_salt', 'salt');
        }

        final container = await restart();
        expect(
          container.read(appBootstrapProvider).initialLocation,
          existingWallet ? '/unlock' : '/welcome',
        );
        expect(container.read(flipToHideBalanceProvider), isFalse);
      },
    );
  }

  for (final legacyDisabled in ['true', 'false']) {
    test('QA disabled=$legacyDisabled does not opt into flip', () async {
      await AppSecureStore.instance.writePlain(
        'zcash_flip_to_hide_balance_disabled',
        legacyDisabled,
      );

      final container = await restart();
      expect(container.read(flipToHideBalanceProvider), isFalse);
    });
  }

  test('an unrecognized saved value leaves flip off', () async {
    await AppSecureStore.instance.writePlain(
      kFlipToHideBalanceEnabledKey,
      'unknown',
    );

    final container = await restart();
    expect(container.read(flipToHideBalanceProvider), isFalse);
  });

  for (final hidden in [false, true]) {
    test(
      'saved choices survive restart without changing hidden=$hidden',
      () async {
        final store = AppSecureStore.instance;
        await store.writePlain(
          kPrivacyModeEnabledKey,
          hidden ? 'true' : 'false',
        );
        final initial = await restart();
        await initial.read(flipToHideBalanceProvider.notifier).set(true);
        expect(initial.read(flipToHideBalanceProvider), isTrue);
        expect(initial.read(privacyModeProvider), hidden);

        final enabled = await restart();
        expect(enabled.read(flipToHideBalanceProvider), isTrue);
        expect(enabled.read(privacyModeProvider), hidden);
        await enabled.read(flipToHideBalanceProvider.notifier).set(false);
        expect(enabled.read(flipToHideBalanceProvider), isFalse);

        final disabled = await restart();
        expect(disabled.read(flipToHideBalanceProvider), isFalse);
        expect(disabled.read(privacyModeProvider), hidden);
        expect(
          await store.readPlain(kPrivacyModeEnabledKey),
          hidden ? 'true' : 'false',
        );
      },
    );
  }
}
