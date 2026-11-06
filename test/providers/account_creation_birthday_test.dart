import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/linux_keyring_coordinator.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _dbName = 'birthday-boundary.db';
const _existing = AccountInfo(uuid: 'existing', name: 'Existing', order: 0);
final _rust = _NoAccountMutationApi();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.initMock(api: _rust));
  tearDownAll(RustLib.dispose);

  for (final additional in [false, true]) {
    for (final fromMnemonic in [false, true]) {
      for (final (label, failure) in <(String, Object)>[
        ('disagreeing heights', StateError('birthday heights disagree')),
        ('timeout', TimeoutException('birthday peer verification timed out')),
        ('cancellation', StateError('birthday verification cancelled')),
      ]) {
        test(
          '${additional ? 'additional' : 'first'} account '
          '${fromMnemonic ? 'from mnemonic' : 'with new mnemonic'} '
          'waits for the birthday boundary and preserves wallet on $label',
          () async {
            _rust.calls.clear();
            SharedPreferences.setMockInitialValues({});
            final initialStorage = <String, String>{
              kWalletDbNameKey: _dbName,
              'zcash_wallet_network': 'main',
              'zcash_active_account': 'existing',
              'zcash_accounts': 'existing account metadata',
              'zcash_account_mnemonic_existing': 'existing stored secret',
            };
            FlutterSecureStorage.setMockInitialValues(Map.of(initialStorage));
            final storage = _RecordingStorage();
            final store = AppSecureStore.testing(
              storage: storage,
              enforceSessionGeneration: false,
              encodeLinuxKeyringValues: false,
            );
            final coordinator = LinuxKeyringCoordinator.testing(enabled: false);
            addTearDown(coordinator.dispose);
            final support = await Directory.systemTemp.createTemp(
              'vizor-creation-birthday-',
            );
            addTearDown(() => support.delete(recursive: true));
            const pathProvider = MethodChannel(
              'plugins.flutter.io/path_provider',
            );
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(
                  pathProvider,
                  (_) async => support.path,
                );
            addTearDown(
              () => TestDefaultBinaryMessengerBinding
                  .instance
                  .defaultBinaryMessenger
                  .setMockMethodCallHandler(pathProvider, null),
            );
            final files = <File, String>{};
            for (final suffix in ['', '-wal', '-shm']) {
              final file = File('${support.path}/$_dbName$suffix');
              final content = 'existing wallet contents $suffix';
              await file.writeAsString(content);
              files[file] = content;
            }
            final birthday = Completer<BigInt>();
            final endpoints = _CreationBirthday(birthday.future);
            final initialState = AccountState(
              accounts: additional ? const [_existing] : const [],
              activeAccountUuid: additional ? _existing.uuid : null,
              activeAddress: additional ? 'u1existing' : null,
            );
            final container = ProviderContainer(
              overrides: [
                appBootstrapProvider.overrideWithValue(
                  _bootstrap(initialState),
                ),
                accountProvider.overrideWith(
                  () => AccountNotifier.testing(store: store),
                ),
                linuxKeyringCoordinatorProvider.overrideWithValue(coordinator),
                rpcEndpointFailoverProvider.overrideWith(() => endpoints),
              ],
            );
            addTearDown(container.dispose);
            await container.read(accountProvider.future);
            final accounts = container.read(accountProvider.notifier);
            final Future<Object?> creation = fromMnemonic
                ? accounts.createAccountFromMnemonic(
                    mnemonic: 'caller provided mnemonic fixture',
                  )
                : accounts.createAccount();
            final failed = expectLater(
              creation,
              throwsA(
                isA<WalletCreationCurrentBlockHeightException>().having(
                  (error) => error.cause,
                  'cause',
                  same(failure),
                ),
              ),
            );
            await pumpEventQueue();
            expect(endpoints.creationReads, 1);
            expect(endpoints.ordinaryReads, 0);
            expect(_rust.calls, isEmpty);
            expect(storage.writes, isEmpty);

            birthday.completeError(failure);
            await failed;

            // Neither first-account replacement nor additional-account writes
            // may happen without the fresh two-endpoint birthday-height check.
            expect(_rust.calls, isEmpty);
            expect(storage.writes, isEmpty);
            expect(await storage.readAll(), initialStorage);
            for (final entry in files.entries) {
              expect(await entry.key.readAsString(), entry.value);
            }
            expect(
              container.read(accountProvider).requireValue,
              same(initialState),
            );
            expect(coordinator.hasPendingMutation, isFalse);
          },
        );
      }
    }
  }
}

AppBootstrapState _bootstrap(AccountState accounts) => AppBootstrapState(
  initialLocation: accounts.hasAccounts ? '/home' : '/welcome',
  initialAccountState: accounts,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: accounts.hasAccounts,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _CreationBirthday extends RpcEndpointFailoverNotifier {
  _CreationBirthday(this.birthday);
  final Future<BigInt> birthday;
  int creationReads = 0;
  int ordinaryReads = 0;

  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: defaultRpcEndpointConfig('main'),
    current: defaultRpcEndpointConfig('main'),
    fallbackCandidates: const [],
  );

  @override
  Future<BigInt> getCreationBirthdayHeight() {
    creationReads++;
    return birthday;
  }

  // An ordinary tip is available but must not authorize account creation.
  @override
  Future<BigInt> getLatestBlockHeight() async {
    ordinaryReads++;
    return BigInt.from(3_000_000);
  }
}

class _NoAccountMutationApi implements RustLibApi {
  final calls = <Symbol>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    throw StateError('Rust must not run before birthday verification');
  }
}

class _RecordingStorage extends FlutterSecureStorage {
  final writes = <String>[];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    writes.add(key);
    return super.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}
