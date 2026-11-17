import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _account = AccountInfo(uuid: 'fixture', name: 'Fixture', order: 0);

class _RestartStore extends AppSecureStore {
  _RestartStore({
    this.failRepair = false,
    this.failCleanup = false,
    this.unavailableMarker = false,
  }) : super.testing(storage: const FlutterSecureStorage());

  final bool failRepair;
  final bool failCleanup;
  final bool unavailableMarker;

  @override
  Future<String?> readPlain(String key) {
    if (unavailableMarker && key == kPrivacyModeRevealPendingKey) {
      throw const SecureStorageUnavailableException(
        operation: 'marker read',
        cause: 'unavailable',
      );
    }
    return super.readPlain(key);
  }

  @override
  Future<void> writePlain(String key, String value) {
    if (failRepair && key == kPrivacyModeEnabledKey && value == 'true') {
      throw StateError('recovery save failed');
    }
    return super.writePlain(key, value);
  }

  @override
  Future<void> delete(String key) {
    if (failCleanup && key == kPrivacyModeRevealPendingKey) {
      throw StateError('marker cleanup failed');
    }
    return super.delete(key);
  }
}

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
      kWalletDbNameKey: 'zcash_wallet_privacy_test.db',
      'zcash_accounts': jsonEncode([_account.toJson()]),
      'zcash_active_account': _account.uuid,
      'zcash_password_verifier': 'verifier',
      'zcash_password_verifier_salt': 'salt',
      kPrivacyModeEnabledKey: 'false',
      kPrivacyModeRevealPendingKey: 'true',
    });
    AppSecureStore.instance.clearSessionPassword();
    final support = await Directory.systemTemp.createTemp(
      'vizor-privacy-boot-',
    );
    addTearDown(() => support.delete(recursive: true));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => support.path);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  test(
    'full bootstrap overrides a saved reveal and repeats failed recovery',
    () async {
      final failed = await loadAppBootstrap(
        secureStore: _RestartStore(failRepair: true),
      );
      expect(failed.hasBlockingFailure, isFalse);
      expect(failed.privacyModeEnabled, isTrue);
      expect(failed.hideBalanceOnUnlockEnabled, isFalse);
      expect(failed.initialLocation, '/unlock');
      expect(
        await const FlutterSecureStorage().read(key: kPrivacyModeEnabledKey),
        'false',
      );
      expect(
        await const FlutterSecureStorage().read(
          key: kPrivacyModeRevealPendingKey,
        ),
        'true',
      );

      // A fresh bootstrap has no previous provider or pending intent.
      final recovered = await loadAppBootstrap(secureStore: _RestartStore());
      expect(recovered.hasBlockingFailure, isFalse);
      expect(recovered.privacyModeEnabled, isTrue);
      expect(
        await const FlutterSecureStorage().read(key: kPrivacyModeEnabledKey),
        'true',
      );
      expect(
        await const FlutterSecureStorage().read(
          key: kPrivacyModeRevealPendingKey,
        ),
        isNull,
      );
    },
  );

  test(
    'failed startup marker cleanup keeps the persisted mask on next launch',
    () async {
      final first = await loadAppBootstrap(
        secureStore: _RestartStore(failCleanup: true),
      );
      expect(first.privacyModeEnabled, isTrue);
      expect(
        await const FlutterSecureStorage().read(key: kPrivacyModeEnabledKey),
        'true',
      );
      final next = await loadAppBootstrap(secureStore: _RestartStore());
      expect(next.hasBlockingFailure, isFalse);
      expect(next.privacyModeEnabled, isTrue);
    },
  );

  test('unavailable marker retains the blocking storage screen', () async {
    final result = await loadAppBootstrap(
      secureStore: _RestartStore(unavailableMarker: true),
    );
    expect(
      result.failureKind,
      AppBootstrapFailureKind.secureStorageUnavailable,
    );
    expect(result.initialLocation, '/storage-unavailable');
    expect(
      await const FlutterSecureStorage().read(
        key: kPrivacyModeRevealPendingKey,
      ),
      'true',
    );
  });

  test(
    'a legacy saved reveal remains visible without a pending marker',
    () async {
      await const FlutterSecureStorage().delete(
        key: kPrivacyModeRevealPendingKey,
      );
      final result = await loadAppBootstrap(secureStore: _RestartStore());
      expect(result.hasBlockingFailure, isFalse);
      expect(result.privacyModeEnabled, isFalse);
    },
  );

  testWidgets(
    'first restored amount frame and semantics contain only the mask',
    (tester) async {
      final storage = _RestartStore(failRepair: true);
      final bootstrap = await tester.runAsync(
        () => loadAppBootstrap(secureStore: storage),
      );
      expect(bootstrap!.hasBlockingFailure, isFalse);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(bootstrap),
          privacyModeProvider.overrideWith(
            () => PrivacyModeNotifier.testing(store: storage),
          ),
        ],
      );
      addTearDown(container.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Text(
                ref.watch(privacyModeProvider) ? '•••••• ZEC' : '123.45 ZEC',
              ),
            ),
          ),
        ),
      );
      expect(find.text('123.45 ZEC'), findsNothing);
      expect(find.bySemanticsLabel('123.45 ZEC'), findsNothing);
      expect(find.bySemanticsLabel('•••••• ZEC'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => storage.readPlain(kPrivacyModeRevealPendingKey),
        ),
        'true',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    },
  );
}
