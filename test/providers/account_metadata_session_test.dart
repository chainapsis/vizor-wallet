import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/linux_keyring_coordinator.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _initialAccounts = AccountState(
  accounts: [
    AccountInfo(uuid: 'account-1', name: 'Primary', order: 0),
    AccountInfo(uuid: 'account-2', name: 'Other', order: 1),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1account-1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final rust = _MetadataRustFake();
  late _DelayedMetadataStore store;
  late LinuxKeyringCoordinator coordinator;
  late ProviderContainer container;
  late _MetadataAccountNotifier account;

  setUpAll(() => RustLib.initMock(api: rust));
  tearDownAll(RustLib.dispose);
  setUp(() async {
    rust.reset();
    FlutterSecureStorage.setMockInitialValues({
      kWalletDbNameKey: 'zcash_wallet_metadata_test.db',
      'zcash_wallet_network': 'main',
    });
    store = _DelayedMetadataStore()..setSessionPassword('Testpass1!');
    coordinator = LinuxKeyringCoordinator.testing();
    account = _MetadataAccountNotifier(store);
    final directory = await Directory.systemTemp.createTemp(
      'account-metadata-',
    );
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (call) async => directory.path);
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        linuxKeyringCoordinatorProvider.overrideWithValue(coordinator),
        accountProvider.overrideWith(() => account),
      ],
    );
    await container.read(accountProvider.future);
    addTearDown(() async {
      await Future<void>.delayed(Duration.zero);
      container.dispose();
      coordinator.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paths, null);
      await directory.delete(recursive: true);
    });
  });

  void lock() {
    store.clearSessionPassword();
    account.clearSensitiveStateForLock();
    expect(container.read(accountProvider).requireValue.activeAddress, isNull);
  }

  for (final mutation in ['rename', 'profile']) {
    test(
      'Linux $mutation keeps a locked address clear after metadata saves',
      () async {
        store.delayWrite('zcash_accounts');
        final operation = mutation == 'rename'
            ? account.renameAccount('account-1', 'Renamed')
            : account.updateProfilePicture('account-1', 'pfp-02');
        await store.writeStarted.future;
        lock();
        store.writeRelease.complete();
        await operation;

        final current = container.read(accountProvider).requireValue;
        expect(current.activeAddress, isNull);
        expect(current.activeAccountUuid, 'account-1');
        final saved =
            (jsonDecode((await store.readPlain('zcash_accounts'))!) as List)
                .cast<Map<String, dynamic>>()
                .first;
        if (mutation == 'rename') {
          expect(current.activeAccount!.name, 'Renamed');
          expect(saved['name'], 'Renamed');
        } else {
          expect(current.activeAccount!.profilePictureId, 'pfp-02');
          expect(saved['profilePictureId'], 'pfp-02');
        }
      },
    );
  }

  test(
    'Linux switch keeps its durable UUID after lock during metadata save',
    () async {
      store.delayWrite('zcash_active_account');
      final operation = account.switchAccount('account-2');
      await store.writeStarted.future;
      lock();
      store.writeRelease.complete();
      await operation;

      final current = container.read(accountProvider).requireValue;
      expect(await store.readPlain('zcash_active_account'), 'account-2');
      expect(current.activeAccountUuid, 'account-2');
      expect(current.activeAddress, isNull);
    },
  );

  test('Linux switch discards an address that completes after lock', () async {
    rust.delayAddress('account-2');
    final operation = account.switchAccount('account-2');
    await rust.addressStarted.future;
    lock();
    rust.addressRelease.complete('u1account-2');
    await operation;

    final current = container.read(accountProvider).requireValue;
    expect(await store.readPlain('zcash_active_account'), 'account-2');
    expect(current.activeAccountUuid, 'account-2');
    expect(current.activeAddress, isNull);
  });

  test(
    'Linux restore discards its address after a lock and unlock cycle',
    () async {
      account.clearSensitiveStateForLock();
      rust.delayAddress('account-1');
      final operation = account.restoreAfterUnlock();
      await rust.addressStarted.future;
      lock();
      store.setSessionPassword('Testpass1!');
      rust.addressRelease.complete('u1stale-address');
      await operation;
      expect(
        container.read(accountProvider).requireValue.activeAddress,
        isNull,
      );
    },
  );

  test(
    'Linux restore cannot switch back after a newer switch succeeds',
    () async {
      account.clearSensitiveStateForLock();
      rust.delayAddress('account-1');
      final operation = account.restoreAfterUnlock();
      await rust.addressStarted.future;
      await account.switchAccount('account-2');
      expect(
        container.read(accountProvider).requireValue.activeAccountUuid,
        'account-2',
      );
      rust.addressRelease.complete('u1stale-account-1');
      await operation;

      final current = container.read(accountProvider).requireValue;
      expect(current.activeAccountUuid, 'account-2');
      expect(current.activeAddress, 'u1account-2');
    },
  );

  test(
    'Linux restore preserves metadata saved while its address was loading',
    () async {
      account.clearSensitiveStateForLock();
      rust.delayAddress('account-1');
      final operation = account.restoreAfterUnlock();
      await rust.addressStarted.future;
      await account.renameAccount('account-1', 'Renamed');
      rust.addressRelease.complete('u1account-1');
      await operation;

      final current = container.read(accountProvider).requireValue;
      expect(current.activeAccount!.name, 'Renamed');
      expect(current.activeAddress, 'u1account-1');
    },
  );

  test(
    'Linux restore cannot republish the account snapshot cleared by reset',
    () async {
      rust.delayAddress('account-1');
      final operation = account.restoreAfterUnlock();
      await rust.addressStarted.future;
      account.publishCompletedReset();
      rust.addressRelease.complete('u1deleted-account');
      await operation;

      final current = container.read(accountProvider).requireValue;
      expect(current.accounts, isEmpty);
      expect(current.activeAccountUuid, isNull);
      expect(current.activeAddress, isNull);
    },
  );
}

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: _initialAccounts,
  initialSyncSnapshot: AppSyncSnapshot.emptyForAccount('account-1'),
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _MetadataAccountNotifier extends AccountNotifier {
  _MetadataAccountNotifier(this.store) : super.testing(store: store);
  final AppSecureStore store;

  // Isolates the late-publication boundary after reset has committed its empty
  // snapshot; the native reset operation itself has separate integration tests.
  void publishCompletedReset() {
    store.clearSessionPassword();
    state = const AsyncData(AccountState());
  }
}

class _DelayedMetadataStore extends AppSecureStore {
  _DelayedMetadataStore()
    : super.testing(
        storage: const FlutterSecureStorage(),
        enforceSessionGeneration: true,
      );
  String? delayedKey;
  final writeStarted = Completer<void>();
  final writeRelease = Completer<void>();

  void delayWrite(String key) => delayedKey = key;

  @override
  Future<void> writeString(String key, String value) async {
    if (key == delayedKey) {
      writeStarted.complete();
      await writeRelease.future;
    }
    await super.writeString(key, value);
  }
}

class _MetadataRustFake implements RustLibApi {
  String? delayedAccount;
  late Completer<void> addressStarted;
  late Completer<String> addressRelease;

  void reset() {
    delayedAccount = null;
    addressStarted = Completer<void>();
    addressRelease = Completer<String>();
  }

  void delayAddress(String uuid) => delayedAccount = uuid;

  @override
  Future<String> crateApiWalletGetUnifiedAddress({
    required String dbPath,
    required String network,
    String? accountUuid,
  }) async {
    if (accountUuid == delayedAccount) {
      addressStarted.complete();
      return addressRelease.future;
    }
    return 'u1$accountUuid';
  }

  @override
  Future<void> crateApiVotingResetVotingSessionState({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
