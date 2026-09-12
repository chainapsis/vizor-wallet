// Real Rust, SQLite and encryption; only OS storage, sync and support paths
// are isolated. Run through scripts/test-wallet-setup.sh.
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/security/software_wallet_secret.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/storage/wallet_recovery.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/create/customise_account_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_customise_account_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/features/onboarding/wallet_recovery_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../figma_compare/figma_compare_font_loader.dart';

const _library = String.fromEnvironment('VIZOR_RECOVERY_NATIVE_LIBRARY');
const _phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _ufvk =
    'uview1s8x5c6zq8pllw2v8ywmcp0fm46d5dk0er8gwwraz2l2s6g0cvq0jlyar820w9z6sh5l285d2ctzcukr2j2fn6cl7nyapa235fxkcmf7xkg4e3pc0phu7e95mukwx3j8t96p7yzuuxhdl9u28letaxay3gyscd9s4tr59dxg4uulsdxjxmy64ls4sy36n8p03j7f0d9w4ycjullvp5lqgslc4agjlgxzk53wnwkcm4andl5xqgs2afa7ewkkfl9fcyw7s5kknzlmn55m6sz93yvqpx78shy0uausk3avw';
const _verifier = 'zcash_password_verifier';
const _verifierSalt = 'zcash_password_verifier_salt';

void runWalletSetupNativeTests({required bool mobile}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_library.isEmpty) {
    test(
      'native wallet setup failures',
      () {},
      skip: 'Run scripts/test-wallet-setup.sh.',
    );
    return;
  }
  final password = mobile ? '123456' : 'Setup123!';
  final store = AppSecureStore.instance;
  late Directory support;
  late _FaultStorage storage;

  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(_library));
    await loadFigmaCompareFonts();
  });
  tearDownAll(RustLib.dispose);
  setUp(() async {
    support = await Directory.systemTemp.createTemp('vizor-setup-test-');
    storage = _FaultStorage();
    FlutterSecureStorage.setMockInitialValues(storage);
    SharedPreferences.setMockInitialValues({});
    store.clearSessionPassword();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? support.path
              : null,
        );
  });
  tearDown(() async {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await support.delete(recursive: true);
  });

  Future<ProviderContainer> container() async {
    final result = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        syncProvider.overrideWith(_NoSync.new),
      ],
    );
    addTearDown(result.dispose);
    await result.read(accountProvider.future);
    return result;
  }

  Future<void> importAccount(ProviderContainer ref, bool hardware) {
    final account = ref.read(accountProvider.notifier);
    return hardware
        ? account.importKeystoneAccount(
            name: 'Setup fixture',
            ufvk: _ufvk,
            seedFingerprint: List.filled(32, 0),
            zip32Index: 0,
            birthdayHeight: 2000000,
          )
        : account.importAccount(
            mnemonic: _phrase,
            birthdayHeight: 2000000,
            name: 'Setup fixture',
          );
  }

  for (final failure in [
    'zcash_accounts',
    'zcash_active_account',
    'zcash_account_mnemonic_',
    'software-active',
    'software-drop-secret',
  ]) {
    test(
      'partial $failure failure preserves credentials and recovers the same DB',
      () async {
        final ref = await container();
        final security = ref.read(appSecurityProvider.notifier);
        final hardware =
            failure == 'zcash_accounts' || failure == 'zcash_active_account';
        await security.preparePasswordSetup(password);
        final verifier = storage[_verifier];
        final salt = storage[_verifierSalt];
        expect(storage[kWalletRecoveryPendingKey], isNotNull);
        if (failure == 'software-drop-secret') {
          storage.dropWritePrefix = 'zcash_account_mnemonic_';
        } else {
          storage.failWritePrefix = failure == 'software-active'
              ? 'zcash_active_account'
              : failure;
        }
        await expectLater(
          importAccount(ref, hardware),
          throwsA(isA<SecureStorageUnavailableException>()),
        );
        final path = await getWalletDbPath();
        final bytes = await File(path).readAsBytes();
        final accounts = await rust.inspectWalletForRecovery(
          dbPath: path,
          network: 'main',
        );
        expect(accounts, hasLength(1));
        await security.rollbackPasswordSetup();
        expect(security.requiresWalletSetupRecovery, isTrue);
        expect(storage[_verifier], verifier);
        expect(storage[_verifierSalt], salt);
        expect(await File(path).readAsBytes(), bytes);
        await expectLater(
          security.preparePasswordSetup(password),
          throwsStateError,
        );
        // Even a stale account-provider snapshot cannot replace this wallet.
        await expectLater(importAccount(ref, hardware), throwsStateError);
        expect(await getWalletDbPath(), path);
        expect(await File(path).readAsBytes(), bytes);
        final restart = await loadAppBootstrap();
        expect(restart.initialLocation, '/wallet-recovery');
        final recovery = WalletRecoverySession(
          candidate: restart.walletRecovery!.candidates.single,
        );
        expect(await recovery.unlockExistingSecrets(password), isTrue);
        final uuid = accounts.single.uuid;
        if (hardware) {
          expect(await recovery.verifyHardwareKey(uuid, _ufvk), isTrue);
        } else {
          expect(recovery.isVerified(uuid), failure == 'software-active');
          expect(
            await recovery.verifySoftwareSecret(
              uuid,
              const SoftwareWalletSecret(mnemonic: _phrase),
            ),
            isTrue,
          );
        }
        await recovery.reconnect();
        expect((await loadAppBootstrap()).initialLocation, '/unlock');
        expect(await store.verifyPassword(password), isTrue);
        if (!hardware) expect(await store.readAccountMnemonic(uuid), _phrase);
        expect(await getWalletDbPath(), path);
        expect(await File(path).readAsBytes(), bytes);
      },
    );
  }

  test(
    'failed preflight restarts safely before a native account exists',
    () async {
      final ref = await container();
      final security = ref.read(appSecurityProvider.notifier);
      await security.preparePasswordSetup(password);
      await expectLater(
        ref
            .read(accountProvider.notifier)
            .importAccount(mnemonic: 'invalid phrase', birthdayHeight: 2000000),
        throwsA(anything),
      );
      expect(await readWalletDbName(), isNotNull);
      await security.rollbackPasswordSetup();
      expect(security.requiresWalletSetupRecovery, isFalse);
      expect(await store.isPasswordConfigured(), isFalse);
      expect(storage[kWalletRecoveryPendingKey], kWalletSetupPendingValue);
      expect(await readWalletDbName(), isNull);
      expect((await loadAppBootstrap()).initialLocation, '/welcome');
      await security.preparePasswordSetup(password);
      await importAccount(ref, false);
      await security.commitPasswordSetup();
      expect(await readWalletDbName(), isNotNull);
      expect(storage[kWalletRecoveryPendingKey], isNull);
      expect(await store.verifyPasswordOnly(password), isTrue);
    },
  );

  test(
    'pre-account setup interruption can resume with a password entry',
    () async {
      final original = await container();
      await original
          .read(appSecurityProvider.notifier)
          .preparePasswordSetup(password);
      store.clearSessionPassword();
      final restart = await loadAppBootstrap();
      expect(restart.initialLocation, '/welcome');
      final resumed = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(restart),
          syncProvider.overrideWith(_NoSync.new),
        ],
      );
      addTearDown(resumed.dispose);
      await resumed.read(accountProvider.future);
      final security = resumed.read(appSecurityProvider.notifier);
      await security.preparePasswordSetup(password);
      await importAccount(resumed, true);
      await security.commitPasswordSetup();
      expect(storage[kWalletRecoveryPendingKey], isNull);
      expect(await store.verifyPasswordOnly(password), isTrue);
    },
  );

  test(
    'allocated DB locator without a file resumes setup in a fresh session',
    () async {
      final birthday = Completer<BigInt>();
      final birthdayRequested = Completer<void>();
      final ref = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          syncProvider.overrideWith(_NoSync.new),
          rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue((
            _,
            _,
          ) {
            birthdayRequested.complete();
            return birthday.future;
          }),
        ],
      );
      addTearDown(ref.dispose);
      await ref.read(accountProvider.future);
      final security = ref.read(appSecurityProvider.notifier);
      await security.preparePasswordSetup(password);
      final interrupted = ref
          .read(accountProvider.notifier)
          .createAccountFromMnemonic(mnemonic: _phrase);
      await birthdayRequested.future.timeout(const Duration(seconds: 5));
      expect(await readWalletDbName(), isNotNull);
      final path = await getWalletDbPath();
      expect(await File(path).exists(), isFalse);
      ref.dispose();
      store.clearSessionPassword();
      final interruptedExpectation = expectLater(
        interrupted,
        throwsA(anything),
      );
      birthday.completeError(StateError('setup interrupted'));
      await interruptedExpectation;

      final restart = await loadAppBootstrap();
      expect(restart.initialLocation, '/welcome');
      final resumed = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(restart),
          syncProvider.overrideWith(_NoSync.new),
          rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
            (_, _) async => BigInt.from(2000000),
          ),
        ],
      );
      addTearDown(resumed.dispose);
      await resumed.read(accountProvider.future);
      final resumedSecurity = resumed.read(appSecurityProvider.notifier);
      await resumedSecurity.preparePasswordSetup(password);
      await resumed
          .read(accountProvider.notifier)
          .createAccountFromMnemonic(
            mnemonic: _phrase,
            name: 'Resumed fixture',
          );
      await resumedSecurity.commitPasswordSetup();
      expect(await getWalletDbPath(), path);
      expect(await File(path).exists(), isTrue);
      expect(storage[kWalletRecoveryPendingKey], isNull);
      expect(await store.verifyPasswordOnly(password), isTrue);
      expect(resumed.read(accountProvider).value!.accounts, hasLength(1));
    },
  );

  test(
    'password configuration interruption preserves the marker and resumes',
    () async {
      final ref = await container();
      final security = ref.read(appSecurityProvider.notifier);
      storage.failWriteKey = _verifier;
      await expectLater(
        security.preparePasswordSetup(password),
        throwsA(isA<SecureStorageUnavailableException>()),
      );
      expect(storage[kWalletRecoveryPendingKey], kWalletSetupPendingValue);
      expect(storage[_verifierSalt], isNotNull);
      expect(storage[_verifier], isNull);
      store.clearSessionPassword();

      final restart = await loadAppBootstrap();
      expect(restart.initialLocation, '/welcome');
      final resumed = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(restart),
          syncProvider.overrideWith(_NoSync.new),
        ],
      );
      addTearDown(resumed.dispose);
      await resumed.read(accountProvider.future);
      final resumedSecurity = resumed.read(appSecurityProvider.notifier);
      await resumedSecurity.preparePasswordSetup(password);
      await importAccount(resumed, true);
      await resumedSecurity.commitPasswordSetup();
      expect(storage[kWalletRecoveryPendingKey], isNull);
      expect(await store.verifyPasswordOnly(password), isTrue);
    },
  );

  test('a silently dropped setup marker blocks password preparation', () async {
    final ref = await container();
    final security = ref.read(appSecurityProvider.notifier);
    storage.dropWritePrefix = kWalletRecoveryPendingKey;
    await expectLater(
      security.preparePasswordSetup(password),
      throwsStateError,
    );
    expect(storage[kWalletRecoveryPendingKey], isNull);
    expect(storage[_verifier], isNull);
    expect(storage[_verifierSalt], isNull);
  });

  test('a rejected setup marker blocks password preparation', () async {
    final ref = await container();
    final security = ref.read(appSecurityProvider.notifier);
    storage.failWriteKey = kWalletRecoveryPendingKey;
    await expectLater(
      security.preparePasswordSetup(password),
      throwsA(isA<SecureStorageUnavailableException>()),
    );
    expect(storage[kWalletRecoveryPendingKey], isNull);
    expect(storage[_verifier], isNull);
    expect(storage[_verifierSalt], isNull);
  });

  test(
    'empty initialized setup DB stays reusable after invalid hardware input',
    () async {
      final ref = await container();
      final security = ref.read(appSecurityProvider.notifier);
      await security.preparePasswordSetup(password);
      await expectLater(
        ref
            .read(accountProvider.notifier)
            .importKeystoneAccount(
              name: 'Invalid fixture',
              ufvk: 'invalid ufvk',
              seedFingerprint: List.filled(32, 0),
              zip32Index: 0,
              birthdayHeight: 2000000,
            ),
        throwsA(anything),
      );
      final path = await getWalletDbPath();
      expect(await File(path).exists(), isTrue);
      await security.rollbackPasswordSetup();
      expect((await loadAppBootstrap()).initialLocation, '/welcome');
      expect(await File(path).exists(), isTrue);
      await security.preparePasswordSetup(password);
      await importAccount(ref, true);
      await security.commitPasswordSetup();
      expect(await getWalletDbPath(), path);
    },
  );

  test('empty setup DB without its stored locator requires recovery', () async {
    final ref = await container();
    final security = ref.read(appSecurityProvider.notifier);
    await security.preparePasswordSetup(password);
    await expectLater(
      ref
          .read(accountProvider.notifier)
          .importKeystoneAccount(
            name: 'Invalid fixture',
            ufvk: 'invalid ufvk',
            seedFingerprint: List.filled(32, 0),
            zip32Index: 0,
            birthdayHeight: 2000000,
          ),
      throwsA(anything),
    );
    final path = await getWalletDbPath();
    final originalBytes = await File(path).readAsBytes();
    storage.data.remove(kWalletDbNameKey);
    store.clearSessionPassword();
    expect((await loadAppBootstrap()).initialLocation, '/wallet-recovery');
    expect(await File(path).readAsBytes(), originalBytes);
    expect(storage[kWalletDbNameKey], isNull);
    expect(await store.verifyPasswordOnly(password), isTrue);
  });

  test(
    'unreadable DB and keyring errors cannot remove prepared credentials',
    () async {
      final ref = await container();
      final security = ref.read(appSecurityProvider.notifier);
      await security.preparePasswordSetup(password);
      await importAccount(ref, true);
      final verifier = storage[_verifier];
      // Missing pointer plus an existing wallet is not an empty installation.
      storage.data.remove(kWalletDbNameKey);
      storage.failReads = true;
      await security.rollbackPasswordSetup();
      storage.failReads = false;
      expect(security.requiresWalletSetupRecovery, isTrue);
      expect(storage[_verifier], verifier);
      expect(storage[kWalletRecoveryPendingKey], isNotNull);
      expect((await loadAppBootstrap()).initialLocation, '/wallet-recovery');
    },
  );

  for (final hardware in [true, false]) {
    testWidgets(
      '${hardware ? 'Keystone' : 'software'} setup failure opens the recovery screen',
      (tester) async {
        await tester.binding.setSurfaceSize(
          mobile ? const Size(393, 852) : const Size(1280, 900),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        storage.failWritePrefix = hardware
            ? 'zcash_active_account'
            : 'zcash_account_mnemonic_';
        AppBootstrapState? restarted;
        late GoRouter router;
        final args = CustomiseAccountArgs(
          pendingPassword: password,
          setupArgs: hardware
              ? SetPasswordScreenArgs.importKeystone(
                  name: 'Keystone fixture',
                  ufvk: _ufvk,
                  seedFingerprint: List.filled(32, 0),
                  zip32Index: 0,
                  birthdayHeight: 2000000,
                )
              : const SetPasswordScreenArgs.importWallet(
                  mnemonic: _phrase,
                  birthdayHeight: 2000000,
                ),
        );
        final ref = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
            syncProvider.overrideWith(_NoSync.new),
            appBootstrapRetryProvider.overrideWithValue(() async {
              restarted = await loadAppBootstrap();
              router.go(restarted!.initialLocation);
            }),
          ],
        );
        addTearDown(ref.dispose);
        await ref.read(accountProvider.future);
        router = GoRouter(
          initialLocation: '/setup',
          routes: [
            GoRoute(
              path: '/setup',
              builder: (_, _) => mobile
                  ? MobileCustomiseAccountScreen(args: args)
                  : CustomiseAccountScreen(args: args),
            ),
            GoRoute(
              path: '/wallet-recovery',
              builder: (_, _) => ProviderScope(
                overrides: [appBootstrapProvider.overrideWithValue(restarted!)],
                child: const WalletRecoveryScreen(),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: ref,
            child: MaterialApp.router(
              routerConfig: router,
              builder: (_, child) => AppTheme(
                data: AppThemeData.dark,
                child: Material(child: child!),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        tester.testTextInput.hide();
        final button = find.byKey(
          ValueKey(
            mobile
                ? 'mobile_customise_account_continue'
                : 'customise_account_finish_button',
          ),
        );
        await tester.ensureVisible(button);
        // Keep global native/storage futures in the real async zone.
        await tester.runAsync(() => tester.tap(button));
        for (var i = 0; i < 200 && restarted == null; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(restarted?.initialLocation, '/wallet-recovery');
        expect(
          router.routeInformationProvider.value.uri.path,
          '/wallet-recovery',
        );
        expect(find.text('Wallet found'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          await tester.runAsync(() => store.verifyPasswordOnly(password)),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
      timeout: const Timeout(Duration(seconds: 40)),
    );
  }
}

class _NoSync extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();
  @override
  bool needsPauseForWalletMutation() => false;
}

class _FaultStorage extends MapBase<String, String> {
  final data = <String, String>{};
  String? failWritePrefix;
  String? failWriteKey;
  String? dropWritePrefix;
  bool failReads = false;
  @override
  Iterable<String> get keys => data.keys;
  @override
  String? operator [](Object? key) {
    if (failReads) throw PlatformException(code: 'fixture_storage_unavailable');
    return data[key];
  }

  @override
  void operator []=(String key, String value) {
    if (failWriteKey == key) {
      failWriteKey = null;
      throw PlatformException(code: 'fixture_storage_write_failure');
    }
    if (failWritePrefix != null && key.startsWith(failWritePrefix!)) {
      failWritePrefix = null;
      throw PlatformException(code: 'fixture_storage_write_failure');
    }
    if (dropWritePrefix != null && key.startsWith(dropWritePrefix!)) {
      dropWritePrefix = null;
      return;
    }
    data[key] = value;
  }

  @override
  String? remove(Object? key) => data.remove(key);
  @override
  void clear() => data.clear();
}
