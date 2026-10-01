import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/security/password_policy.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/gift_wallet_setup.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as wallet;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/payment_links_screen_support.dart' show incomingLink;

const _passcode = kWalletPasswordMinLength == 6 ? '135790' : '13579086';
const _dbName = 'gift-setup-restart.db';
const _existingSecretKey = 'zcash_account_mnemonic_existing-account';
const _existingSecret = 'unchanged-existing-account-secret';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _SetupRustApi();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  late File database;
  late AppSecureStore store;
  late WidgetRef widgetRef;
  late ProviderContainer container;

  setUp(() async {
    api.reset();
    FlutterSecureStorage.setMockInitialValues({kWalletDbNameKey: _dbName});
    SharedPreferences.setMockInitialValues({});
    AppSecureStore.instance.clearSessionPassword();
    store = AppSecureStore.testing(storage: const FlutterSecureStorage());
    addTearDown(store.clearSessionPassword);
    final support = await Directory.systemTemp.createTemp('vizor-gift-setup-');
    database = File('${support.path}/$_dbName');
    addTearDown(() => support.delete(recursive: true));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => support.path);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  });

  Future<void> mount(
    WidgetTester tester, {
    AppBootstrapState? bootstrap,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            bootstrap ?? AppBootstrapState.empty,
          ),
          accountProvider.overrideWith(
            () => AccountNotifier.testing(store: store),
          ),
          appSecurityProvider.overrideWith(
            () => AppSecurityNotifier.testing(store: store),
          ),
          syncProvider.overrideWith(_IdleSync.new),
          rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
            (_, _) async => BigInt.from(3000000),
          ),
        ],
        child: Consumer(
          builder: (_, ref, _) {
            widgetRef = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    container = ProviderScope.containerOf(
      tester.element(find.byType(Consumer)),
    );
    await container.read(accountProvider.future);
  }

  Future<String> setUpWallet() => setUpGiftCardWallet(
    widgetRef,
    passcode: _passcode,
    link: incomingLink,
    accountName: 'Gift account',
    profilePictureId: 'pfp-11',
  );

  Future<void> seedExistingDb() async {
    await database.writeAsString('preexisting database bytes');
    await store.writePlain(_existingSecretKey, _existingSecret);
    api.listFails = true;
  }

  Future<void> expectExistingDataUntouched() async {
    expect(await database.readAsString(), 'preexisting database bytes');
    expect(await store.readPlain(_existingSecretKey), _existingSecret);
    expect(api.generateCalls, 0);
    expect(api.importCalls, 0);
  }

  testWidgets(
    'a failed initial DB guard rolls back setup and permits passcode setup after restart',
    (tester) async {
      await tester.runAsync(seedExistingDb);
      await mount(tester);
      await tester.runAsync(() async {
        await expectLater(
          setUpWallet(),
          throwsA(isA<WalletAccountStateUncertainException>()),
        );
        expect(
          container.read(appSecurityProvider).isPasswordConfigured,
          isFalse,
        );
        expect(await store.isPasswordConfigured(), isFalse);
        expect(
          await store.readPlain(kPendingAccountMnemonicStorageKey),
          isNull,
        );
        expect(store.hasSessionPassword, isFalse);
        await expectExistingDataUntouched();

        store.clearSessionPassword();
        final restarted = await loadAppBootstrap(secureStore: store);
        expect(restarted.hasBlockingFailure, isFalse);
        expect(restarted.initialLocation, '/welcome');
        expect(restarted.hasWallet, isFalse);
        expect(restarted.isPasswordConfigured, isFalse);
        expect(restarted.isUnlocked, isFalse);
        final next = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(restarted),
            appSecurityProvider.overrideWith(
              () => AppSecurityNotifier.testing(store: store),
            ),
          ],
        );
        addTearDown(next.dispose);
        await next
            .read(appSecurityProvider.notifier)
            .preparePasswordSetup(_passcode);
        expect(
          next.read(appSecurityProvider.notifier).hasPreparedPasswordSetup,
          isTrue,
        );
        await next.read(appSecurityProvider.notifier).rollbackPasswordSetup();
        await expectExistingDataUntouched();
      });
    },
  );

  testWidgets(
    'an existing wallet refuses setup without changing any stored value',
    (tester) async {
      late AppBootstrapState bootstrap;
      late Map<String, String> storedBefore;
      await tester.runAsync(() async {
        await seedExistingDb();
        await store.configurePassword(_passcode);
        await store.writeString(
          'zcash_accounts',
          jsonEncode([
            const AccountInfo(
              uuid: 'existing-account',
              name: 'Existing',
              order: 0,
            ).toJson(),
          ]),
        );
        store.clearSessionPassword();
        bootstrap = await loadAppBootstrap(secureStore: store);
        expect(bootstrap.initialLocation, '/unlock');
        expect(bootstrap.isPasswordConfigured, isTrue);
        storedBefore = await const FlutterSecureStorage().readAll();
      });
      await mount(tester, bootstrap: bootstrap);
      await tester.runAsync(() async {
        await expectLater(setUpWallet(), throwsStateError);
        expect(await const FlutterSecureStorage().readAll(), storedBefore);
        expect(
          container.read(appSecurityProvider).isPasswordConfigured,
          isTrue,
        );
        expect(store.hasSessionPassword, isFalse);
        await expectExistingDataUntouched();
      });
    },
  );

  testWidgets(
    'an uncertain import retains the passcode and journal across restart',
    (tester) async {
      await mount(tester);
      await tester.runAsync(() async {
        await expectLater(
          setUpWallet(),
          throwsA(isA<GiftClaimAccountCreatedException>()),
        );
        expect(api.generateCalls, 1);
        expect(api.importCalls, 1);
        expect(await database.exists(), isTrue);
        expect(
          container.read(appSecurityProvider).isPasswordConfigured,
          isTrue,
        );
        expect(await store.isPasswordConfigured(), isTrue);
        final journal = await store.readPlain(
          kPendingAccountMnemonicStorageKey,
        );
        expect(journal, isNotNull);
        store.clearSessionPassword();
        final restarted = await loadAppBootstrap(secureStore: store);
        expect(restarted.hasBlockingFailure, isTrue);
        expect(restarted.initialLocation, '/storage-unavailable');
        expect(
          await store.readPlain(kPendingAccountMnemonicStorageKey),
          journal,
        );
        expect(await store.isPasswordConfigured(), isTrue);
      });
    },
  );
}

class _IdleSync extends FakeSyncNotifier {
  @override
  bool needsPauseForWalletMutation() => false;
}

class _SetupRustApi implements RustLibApi {
  bool listFails = false;
  int generateCalls = 0;
  int importCalls = 0;

  void reset() {
    listFails = false;
    generateCalls = 0;
    importCalls = 0;
  }

  @override
  bool crateApiWalletWalletExists({required String dbPath}) =>
      File(dbPath).existsSync();

  @override
  Future<void> crateApiWalletEnsureWalletDbMigrated({
    required String dbPath,
    required String network,
  }) async {}

  @override
  Future<List<wallet.AccountInfo>> crateApiWalletListAccounts({
    required String dbPath,
    required String network,
  }) async {
    if (listFails) throw StateError('DB inspection failed');
    return [];
  }

  @override
  String crateApiWalletGenerateMnemonic() {
    generateCalls++;
    return 'fresh gift wallet mnemonic';
  }

  @override
  Future<wallet.WalletImportResult> crateApiWalletImportWallet({
    required String mnemonic,
    required String bip39Passphrase,
    BigInt? birthdayHeight,
    required String network,
    required String dbPath,
    String? accountName,
  }) async {
    importCalls++;
    File(dbPath).writeAsStringSync('new account committed to DB');
    listFails = true;
    throw StateError('import result interrupted after creation');
  }

  @override
  Future<String> crateApiSecretDeriveSecretPasswordVerifier({
    required String password,
    required String saltBase64,
  }) async => base64Encode(utf8.encode('$saltBase64:$password'));

  @override
  Future<String> crateApiSecretEncryptSecretPayload({
    required List<int> plainBytes,
    required String password,
    required String saltBase64,
  }) async => jsonEncode({
    'v': 1,
    'n': 'bm9uY2U=',
    'c': base64Encode(plainBytes),
    'm': base64Encode(utf8.encode('$saltBase64:$password')),
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
