// Run with scripts/test-wallet-recovery.sh. Uses the real Rust bridge, wallet
// SQLite schema, seed derivation and secret encryption. Only the OS key store
// and app-support path are replaced; no user wallet or network is accessed.
import 'dart:io';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/security/software_wallet_secret.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/storage/wallet_recovery.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_text_field.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';
import 'package:zcash_wallet/src/features/onboarding/wallet_recovery_screen.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

const _nativeLibrary = String.fromEnvironment('VIZOR_RECOVERY_NATIVE_LIBRARY');
const _captureDirectory = String.fromEnvironment('VIZOR_RECOVERY_CAPTURE_DIR');
const _mobile = kAppFormFactor == AppFormFactor.mobile;
const _password = _mobile ? '123456' : 'Recovery1!';
const _newPassword = _mobile ? '654321' : 'Recovered2!';
const _phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _secondPhrase =
    'legal winner thank year wave sausage worth useful legal winner thank yellow';
// Orchard + transparent UFVK derived from the public _phrase fixture at index 0.
const _keystoneUfvk =
    'uview1s8x5c6zq8pllw2v8ywmcp0fm46d5dk0er8gwwraz2l2s6g0cvq0jlyar820w9z6sh5l285d2ctzcukr2j2fn6cl7nyapa235fxkcmf7xkg4e3pc0phu7e95mukwx3j8t96p7yzuuxhdl9u28letaxay3gyscd9s4tr59dxg4uulsdxjxmy64ls4sy36n8p03j7f0d9w4ycjullvp5lqgslc4agjlgxzk53wnwkcm4andl5xqgs2afa7ewkkfl9fcyw7s5kknzlmn55m6sz93yvqpx78shy0uausk3avw';
const _dbName = 'zcash_wallet_recovery_fixture.db';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_nativeLibrary.isEmpty) {
    test(
      'native wallet recovery integration',
      () {},
      skip:
          'Run scripts/test-wallet-recovery.sh to build and load the real Rust library.',
    );
    return;
  }

  late Directory support;
  late _FaultStorage backend;
  final store = AppSecureStore.instance;
  File getDb() => File('${support.path}/$_dbName');

  Future<String> createWallet({
    bool metadata = true,
    String dbName = _dbName,
    String phrase = _phrase,
  }) async {
    final result = await rust.importWallet(
      mnemonic: phrase,
      bip39Passphrase: '',
      birthdayHeight: BigInt.from(2_000_000),
      network: 'main',
      dbPath: '${support.path}/$dbName',
      accountName: 'Recovery fixture',
    );
    if (metadata) {
      await store.configurePassword(_password);
      await store.writeAccountMnemonic(result.accountUuid, phrase);
      await store.writeString(
        'zcash_accounts',
        jsonEncode([
          {'uuid': result.accountUuid, 'name': 'Recovery fixture', 'order': 0},
        ]),
      );
      await store.writeString('zcash_active_account', result.accountUuid);
      await store.writeString('zcash_wallet_network', 'main');
      await store.writePlain(kWalletDbNameKey, dbName);
      store.clearSessionPassword();
      expect((await loadAppBootstrap()).initialLocation, '/unlock');
    }
    return result.accountUuid;
  }

  Future<WalletRecoverySession> recoverySession() async {
    final state = await loadAppBootstrap();
    expect(state.initialLocation, '/wallet-recovery');
    expect(state.walletRecovery, isNotNull);
    return WalletRecoverySession(
      candidate: state.walletRecovery!.candidates.firstWhere(
        (c) => c.fileName == _dbName,
      ),
    );
  }

  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(_nativeLibrary));
    await loadFigmaCompareFonts();
  });
  tearDownAll(RustLib.dispose);
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    support = await Directory.systemTemp.createTemp('vizor-recovery-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return support.path;
            }
            return null;
          },
        );
    backend = _FaultStorage();
    FlutterSecureStorage.setMockInitialValues(backend);
    SharedPreferences.setMockInitialValues({});
    store.clearSessionPassword();
  });
  tearDown(() async {
    store.clearSessionPassword();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    FlutterSecureStorage.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = null;
    await support.delete(recursive: true);
  });

  test(
    'fresh startup does not allocate a DB name or create a database',
    () async {
      final state = await loadAppBootstrap();
      expect(state.initialLocation, '/welcome');
      expect(await store.readPlain(kWalletDbNameKey), isNull);
      expect(await support.list().toList(), isEmpty);
      await expectLater(getWalletDbPath(), throwsStateError);
    },
  );

  test(
    'normal startup and account-list-only loss retain the existing DB',
    () async {
      final uuid = await createWallet();
      backend.data.remove('zcash_accounts');
      final state = await loadAppBootstrap();
      expect(state.initialLocation, '/unlock');
      expect(state.initialAccountState.activeAccountUuid, uuid);
      expect(await getWalletDbPath(), getDb().path);
    },
  );

  test(
    'missing pointer reconnects with saved secrets and survives restart',
    () async {
      final uuid = await createWallet();
      final original = await getDb().readAsBytes();
      backend.data.remove(kWalletDbNameKey);
      final session = await recoverySession();
      expect(await store.readPlain(kWalletDbNameKey), isNull);
      expect(await session.unlockExistingSecrets(_password), isTrue);
      expect(session.isVerified(uuid), isTrue);
      await session.reconnect();
      expect(store.hasSessionPassword, isFalse);
      final restarted = await loadAppBootstrap();
      expect(restarted.initialLocation, '/unlock');
      expect(restarted.initialAccountState.activeAccountUuid, uuid);
      expect(await getWalletDbPath(), getDb().path);
      expect(await getDb().readAsBytes(), original);
    },
  );

  test(
    'total metadata loss requires the matching recovery phrase before reconnecting',
    () async {
      final uuid = await createWallet();
      final original = await getDb().readAsBytes();
      backend.data.clear();
      final session = await recoverySession();
      expect(session.canReconnect, isFalse);
      await expectLater(
        session.reconnect(newPassword: _newPassword),
        throwsStateError,
      );
      expect(backend.data, isEmpty);
      expect(
        await session.verifySoftwareSecret(
          uuid,
          const SoftwareWalletSecret(mnemonic: _secondPhrase),
        ),
        isFalse,
      );
      expect(
        await session.verifySoftwareSecret(
          uuid,
          const SoftwareWalletSecret(mnemonic: _phrase),
        ),
        isTrue,
      );
      await session.reconnect(newPassword: _newPassword);
      final restarted = await loadAppBootstrap();
      expect(restarted.initialLocation, '/unlock');
      expect(restarted.initialAccountState.activeAccountUuid, uuid);
      expect(await store.verifyPassword(_newPassword), isTrue);
      expect(await store.readAccountMnemonic(uuid), _phrase);
      expect(await getDb().readAsBytes(), original);
    },
  );

  test(
    'a stale pointer is replaced only after account-key verification',
    () async {
      await createWallet();
      backend.data[kWalletDbNameKey] = 'zcash_wallet_nonexistent.db';
      final session = await recoverySession();
      expect(
        await store.readPlain(kWalletDbNameKey),
        'zcash_wallet_nonexistent.db',
      );
      expect(await session.unlockExistingSecrets(_password), isTrue);
      await session.reconnect();
      expect(await getWalletDbPath(), getDb().path);
      expect(
        File('${support.path}/zcash_wallet_nonexistent.db').existsSync(),
        isFalse,
      );
    },
  );

  test(
    'multiple candidates are preserved and a different wallet cannot be adopted',
    () async {
      await createWallet();
      await createWallet(
        metadata: false,
        dbName: 'zcash_wallet_other.db',
        phrase: _secondPhrase,
      );
      final other = File('${support.path}/zcash_wallet_other.db');
      final originalOther = await other.readAsBytes();
      backend.data.remove(kWalletDbNameKey);
      final state = await loadAppBootstrap();
      expect(state.walletRecovery!.candidates, hasLength(2));
      expect(await store.readPlain(kWalletDbNameKey), isNull);
      final wrong = WalletRecoverySession(
        candidate: state.walletRecovery!.candidates.firstWhere(
          (c) => c.fileName == 'zcash_wallet_other.db',
        ),
      );
      expect(await wrong.unlockExistingSecrets(_password), isTrue);
      expect(wrong.canReconnect, isFalse);
      await expectLater(wrong.reconnect(), throwsStateError);
      expect(await other.readAsBytes(), originalOther);
      expect(getDb().existsSync(), isTrue);
    },
  );

  test(
    'a healthy current pointer is not switched to an orphan wallet',
    () async {
      final uuid = await createWallet();
      await createWallet(
        metadata: false,
        dbName: 'zcash_wallet_old.db',
        phrase: _secondPhrase,
      );
      final state = await loadAppBootstrap();
      expect(state.walletRecovery, isNull);
      expect(state.initialAccountState.activeAccountUuid, uuid);
      expect(await getWalletDbPath(), getDb().path);
      expect(File('${support.path}/zcash_wallet_old.db').existsSync(), isTrue);
    },
  );

  test('a mismatched network and corrupt DB remain recovery errors', () async {
    await createWallet();
    backend.data.remove(kWalletDbNameKey);
    backend.data['zcash_wallet_network'] = 'test';
    var state = await loadAppBootstrap();
    expect(state.initialLocation, '/wallet-recovery');
    expect(state.walletRecovery!.candidates.single.error, isNotNull);
    backend.data['zcash_wallet_network'] = 'main';
    await getDb().writeAsString('corrupt fixture');
    state = await loadAppBootstrap();
    expect(state.initialLocation, '/wallet-recovery');
    expect(state.walletRecovery!.candidates.single.error, isNotNull);
    expect(await getDb().readAsString(), 'corrupt fixture');
    expect(await store.readPlain(kWalletDbNameKey), isNull);
  });

  test(
    'unavailable storage remains blocked rather than appearing empty',
    () async {
      await createWallet();
      final before = Map<String, String>.of(backend.data);
      backend.failReads = true;
      final state = await loadAppBootstrap();
      expect(state.initialLocation, '/storage-unavailable');
      expect(
        state.failureKind,
        AppBootstrapFailureKind.secureStorageUnavailable,
      );
      expect(backend.data, before);
      expect(getDb().existsSync(), isTrue);
    },
  );

  test(
    'interrupted locator writes return to recovery and can be retried',
    () async {
      final uuid = await createWallet();
      final original = await getDb().readAsBytes();
      backend.data.remove(kWalletDbNameKey);
      var session = await recoverySession();
      await session.unlockExistingSecrets(_password);
      backend.failWriteKey = 'zcash_active_account';
      await expectLater(
        session.reconnect(),
        throwsA(isA<SecureStorageUnavailableException>()),
      );
      expect(backend.data[kWalletRecoveryPendingKey], _dbName);
      session.dispose();
      session = await recoverySession();
      expect(await session.unlockExistingSecrets(_password), isTrue);
      await session.reconnect();
      expect(backend.data[kWalletRecoveryPendingKey], isNull);
      expect(
        (await loadAppBootstrap()).initialAccountState.activeAccountUuid,
        uuid,
      );
      expect(await getDb().readAsBytes(), original);
    },
  );

  test(
    'a write acknowledged without persistence cannot complete recovery',
    () async {
      await createWallet();
      backend.data.remove(kWalletDbNameKey);
      final session = await recoverySession();
      await session.unlockExistingSecrets(_password);
      backend.dropWriteKey = kWalletDbNameKey;
      await expectLater(session.reconnect(), throwsStateError);
      expect((await loadAppBootstrap()).initialLocation, '/wallet-recovery');
      expect(backend.data[kWalletRecoveryPendingKey], _dbName);
      await session.reconnect();
      expect((await loadAppBootstrap()).initialLocation, '/unlock');
    },
  );

  test(
    'partial multi-seed recovery identifies the missing account and preserves the DB',
    () async {
      final first = await createWallet();
      final second = await rust.addAccount(
        dbPath: getDb().path,
        network: 'main',
        name: 'Second',
        mnemonic: _secondPhrase,
        bip39Passphrase: '',
        birthdayHeight: BigInt.from(2_000_000),
      );
      backend.data.remove(kWalletDbNameKey);
      final original = await getDb().readAsBytes();
      final session = await recoverySession();
      await session.unlockExistingSecrets(_password);
      expect(session.isVerified(first), isTrue);
      expect(session.isVerified(second.accountUuid), isFalse);
      expect(session.canReconnect, isFalse);
      await expectLater(session.reconnect(), throwsStateError);
      expect(await getDb().readAsBytes(), original);
      expect(
        await session.verifySoftwareSecret(
          second.accountUuid,
          const SoftwareWalletSecret(mnemonic: _secondPhrase),
        ),
        isTrue,
      );
      await session.reconnect();
      expect(
        (await loadAppBootstrap()).initialAccountState.accounts,
        hasLength(2),
      );
    },
  );

  test(
    'a pending recovery is honored even if the old pointer still exists',
    () async {
      await createWallet();
      backend.data[kWalletRecoveryPendingKey] = _dbName;
      expect((await loadAppBootstrap()).initialLocation, '/wallet-recovery');
    },
  );

  test(
    'WAL remnants and symlinks are evidence, not a fresh installation',
    () async {
      final wal = File('${getDb().path}-wal');
      await wal.writeAsString('orphan WAL fixture');
      var state = await loadAppBootstrap();
      expect(state.initialLocation, '/wallet-recovery');
      expect(state.walletRecovery!.candidates.single.canInspect, isFalse);
      expect(await wal.readAsString(), 'orphan WAL fixture');
      await wal.delete();
      await Link(getDb().path).create('${support.path}/missing-target.db');
      state = await loadAppBootstrap();
      expect(state.initialLocation, '/wallet-recovery');
      expect(state.walletRecovery!.candidates.single.canInspect, isFalse);
    },
  );

  test(
    'completed reset does not recreate or resurrect the deleted wallet',
    () async {
      await createWallet();
      for (final entity in await support.list().toList()) {
        await entity.delete();
      }
      backend.data.clear();
      final state = await loadAppBootstrap();
      expect(state.initialLocation, '/welcome');
      expect(backend.data[kWalletDbNameKey], isNull);
      expect(await support.list().toList(), isEmpty);
    },
  );

  test(
    'hardware-first recovery needs the independent device key and retains hardware identity',
    () async {
      final hardware = await rust.importHardwareAccount(
        dbPath: getDb().path,
        network: 'main',
        name: 'Hardware fixture',
        ufvkString: _keystoneUfvk,
        seedFingerprint: List<int>.filled(32, 1),
        zip32Index: 0,
        birthdayHeight: BigInt.from(2_000_000),
      );
      final original = await getDb().readAsBytes();
      final session = await recoverySession();
      expect(session.canReconnect, isFalse);
      expect(session.candidate.accounts.single.isSeedAnchor, isFalse);
      expect(
        await session.verifyHardwareKey(hardware.accountUuid, _keystoneUfvk),
        isTrue,
      );
      await session.reconnect(newPassword: _newPassword);
      final restarted = await loadAppBootstrap();
      expect(restarted.initialLocation, '/unlock');
      expect(restarted.initialAccountState.accounts.single.isHardware, isTrue);
      expect(await getDb().readAsBytes(), original);
    },
  );

  for (final allMetadataMissing in [false, true]) {
    testWidgets(
      allMetadataMissing
          ? 'recovery UI restores signing material after total metadata loss'
          : 'recovery UI verifies saved keys and restarts on the same wallet',
      (tester) async {
        final uuid = await tester.runAsync(() => createWallet());
        if (allMetadataMissing) {
          backend.data.clear();
        } else {
          backend.data.remove(kWalletDbNameKey);
        }
        final bootstrap = (await tester.runAsync(loadAppBootstrap))!;
        AppBootstrapState? restarted;
        final boundary = GlobalKey();
        tester.view.physicalSize = _mobile
            ? const Size(390, 844)
            : const Size(1080, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appBootstrapProvider.overrideWithValue(bootstrap),
              appBootstrapRetryProvider.overrideWithValue(() async {
                restarted = await loadAppBootstrap();
              }),
            ],
            child: MaterialApp(
              home: AppTheme(
                data: AppThemeData.dark,
                child: RepaintBoundary(
                  key: boundary,
                  child: const WalletRecoveryScreen(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Recover your wallet'), findsOneWidget);
        expect(find.text('Create wallet'), findsNothing);
        await _capture(
          tester,
          boundary,
          allMetadataMissing ? 'loss-discovery' : 'discovery',
        );
        debugPrint('recovery UI: selecting candidate');
        await tester.tap(find.text('Recover this wallet'));
        await tester.pump(const Duration(milliseconds: 100));
        debugPrint('recovery UI: entering credential');
        if (allMetadataMissing) {
          await tester.tap(find.text('Enter recovery phrase'));
          await tester.pump();
          await _enterField(tester, 'Recovery phrase', _phrase);
          await tester.ensureVisible(find.text('Verify recovery phrase'));
          await _tapNativeAction(tester, find.text('Verify recovery phrase'));
        } else if (_mobile) {
          await _enterPasscode(tester, _password);
        } else {
          await _enterField(tester, 'Password', _password);
          await _tapNativeAction(tester, find.text('Continue'));
        }
        await _pumpUntil(
          tester,
          () => find.text('Recovery material verified').evaluate().isNotEmpty,
        );
        expect(find.text('Recovery phrase needed'), findsNothing);
        debugPrint('recovery UI: account verified');
        await _capture(
          tester,
          boundary,
          allMetadataMissing ? 'loss-verified' : 'verified',
        );
        if (allMetadataMissing && _mobile) {
          await _enterPasscode(tester, _newPassword);
          await _enterPasscode(tester, _newPassword);
        } else {
          if (allMetadataMissing) {
            await _enterField(tester, 'New password', _newPassword);
            await _enterField(tester, 'Confirm password', _newPassword);
          }
          await tester.ensureVisible(find.text('Reconnect wallet'));
          await _tapNativeAction(tester, find.text('Reconnect wallet'));
        }
        await _pumpUntil(tester, () => restarted != null);
        expect(restarted!.initialLocation, '/unlock');
        expect(restarted!.initialAccountState.activeAccountUuid, uuid);
        expect(await tester.runAsync(getWalletDbPath), getDb().path);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}

// Native actions must create their persistent storage-lock futures in the
// real async zone, so a subsequent widget test can consume those futures.
Future<void> _tapNativeAction(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() => tester.tap(finder));
  await tester.pump();
}

Future<void> _enterField(
  WidgetTester tester,
  String label,
  String value,
) async {
  final field = find.byWidgetPredicate(
    (widget) => widget is AppTextField && widget.label == label,
  );
  await tester.ensureVisible(field);
  await tester.enterText(
    find.descendant(of: field, matching: find.byType(EditableText)),
    value,
  );
}

Future<void> _enterPasscode(WidgetTester tester, String passcode) async {
  final keypad = tester.widget<PasscodeNumpad>(find.byType(PasscodeNumpad));
  expect(keypad.onHelp, isNull);
  for (final digit in passcode.split('')) {
    final key = find.bySemanticsLabel('Digit $digit');
    await tester.ensureVisible(key);
    await _tapNativeAction(tester, key);
    await tester.pump();
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  expect(
    done(),
    isTrue,
    reason:
        'The native recovery operation did not reach its expected UI state.',
  );
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (_captureDirectory.isEmpty) return;
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: .75);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_captureDirectory).create(recursive: true);
    await File(
      '$_captureDirectory/${_mobile ? 'mobile' : 'desktop'}-$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

class _FaultStorage extends MapBase<String, String> {
  final data = <String, String>{};
  bool failReads = false;
  String? failWriteKey;
  String? dropWriteKey;

  @override
  Iterable<String> get keys => data.keys;

  @override
  String? operator [](Object? key) {
    if (failReads) throw PlatformException(code: 'fixture_storage_unavailable');
    return data[key];
  }

  @override
  void operator []=(String key, String value) {
    if (key == failWriteKey) {
      failWriteKey = null;
      throw PlatformException(code: 'fixture_write_interrupted');
    }
    if (key == dropWriteKey) {
      dropWriteKey = null;
      return;
    }
    data[key] = value;
  }

  @override
  String? remove(Object? key) => data.remove(key);

  @override
  void clear() => data.clear();
}
