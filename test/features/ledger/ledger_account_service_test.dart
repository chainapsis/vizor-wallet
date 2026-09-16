import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart';

void main() {
  for (final pendingPassword in [null, 'Password1!']) {
    for (final fails in [false, true]) {
      test(
        'account setup password=$pendingPassword import failure=$fails',
        () async {
          final events = <String>[];
          final security = _RecordingSecurityNotifier(events);
          final container = ProviderContainer(
            overrides: [
              appSecurityProvider.overrideWith(() => security),
              ledgerAccountImporterProvider.overrideWithValue(({
                required name,
                required account,
                required birthdayHeight,
                required profilePictureId,
              }) async {
                events.add('import');
                if (fails) throw StateError('import failed');
              }),
            ],
          );
          addTearDown(container.dispose);
          final result = container.read(ledgerAccountSetupProvider)(
            name: 'Ledger',
            account: const LedgerDeviceAccount(
              ufvk: 'uview-test',
              seedFingerprint: [1],
              accountIndex: 0,
              appVersion: '3.9.3',
            ),
            birthdayHeight: 3000000,
            profilePictureId: kDefaultProfilePictureId,
            pendingPassword: pendingPassword,
          );
          if (fails) {
            await expectLater(result, throwsStateError);
          } else {
            await result;
          }
          expect(
            events,
            pendingPassword == null
                ? ['import']
                : ['prepare', 'import', if (fails) 'rollback' else 'commit'],
          );
        },
      );
    }
  }

  test(
    'imports account metadata and USB model without a wallet identity',
    () async {
      final notifier = _CapturingAccountNotifier();
      final container = ProviderContainer(
        overrides: [accountProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await container.read(ledgerAccountImporterProvider)(
        name: 'Ledger',
        account: const LedgerDeviceAccount(
          ufvk: 'uview-test',
          seedFingerprint: [1, 2, 3],
          accountIndex: 7,
          appVersion: '3.9.3',
          deviceModel: 'Ledger Nano S Plus',
        ),
        birthdayHeight: 3000000,
        profilePictureId: kDefaultProfilePictureId,
      );
      expect(notifier.importedUfvk, 'uview-test');
      expect(notifier.importedIndex, 7);
      expect(notifier.importedSeedFingerprint, [1, 2, 3]);
      expect(notifier.importedDeviceModel, 'Ledger Nano S Plus');
    },
  );

  test('imports Bluetooth device metadata as separate raw fields', () async {
    final notifier = _CapturingAccountNotifier();
    final container = ProviderContainer(
      overrides: [accountProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);

    await container.read(ledgerAccountImporterProvider)(
      name: 'Ledger',
      account: const LedgerDeviceAccount(
        ufvk: 'uview-test',
        seedFingerprint: [1, 2, 3],
        accountIndex: 7,
        appVersion: '3.9.3',
        transport: LedgerConnectionTransport.bluetooth,
        deviceId: 'device-1',
        deviceName: 'Rowan Ledger',
        deviceModel: 'Nano X',
      ),
      birthdayHeight: 3000000,
      profilePictureId: kDefaultProfilePictureId,
    );

    expect(notifier.importedTransport, LedgerConnectionTransport.bluetooth);
    expect(notifier.importedDeviceId, 'device-1');
    expect(notifier.importedDeviceName, 'Rowan Ledger');
    expect(notifier.importedDeviceModel, 'Nano X');
  });

  test(
    'Bluetooth account export connects and verifies the selected device first',
    () async {
      final events = <String>[];
      const selected = LedgerBleDevice(
        id: 'device-b',
        name: 'Ledger B',
        model: 'Nano X',
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap()),
          ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.iOS),
          ledgerMobileBleServiceProvider.overrideWithValue(_UnusedBleService()),
          ledgerBluetoothSessionConnectorProvider.overrideWithValue((
            device,
          ) async {
            events.add('connect:${device.id}');
            return '3.9.3';
          }),
          ledgerMobileAccountExporterProvider.overrideWithValue(({
            required mobile,
            required accountIndex,
            required networkName,
          }) async {
            expect(events, ['connect:device-b']);
            events.add('export:$accountIndex:$networkName');
            return LedgerAccountExport(
              ufvk: 'uview-device-b',
              seedFingerprint: Uint8List.fromList([1, 2, 3]),
              accountIndex: accountIndex,
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      final account = await container.read(
        ledgerBluetoothAccountConnectorProvider,
      )(7, selected);

      expect(events, ['connect:device-b', 'export:7:main']);
      expect(account.ufvk, 'uview-device-b');
      expect(account.appVersion, '3.9.3');
      expect(account.deviceId, 'device-b');
      expect(account.deviceName, 'Ledger B');
    },
  );

  for (final sameUfvk in [true, false]) {
    test(
      'duplicate check compares UFVK, not account index: $sameUfvk',
      () async {
        final container = ProviderContainer(
          overrides: [
            accountProvider.overrideWith(
              () => _CapturingAccountNotifier(
                const AccountState(
                  accounts: [
                    AccountInfo(
                      uuid: 'existing',
                      name: 'Existing',
                      order: 0,
                      isHardware: true,
                      hardwareSignerKind: HardwareSignerKind.ledger,
                      zip32AccountIndex: 0,
                    ),
                  ],
                ),
              ),
            ),
            ledgerAccountUfvkLoaderProvider.overrideWithValue((uuid) async {
              expect(uuid, 'existing');
              return sameUfvk ? 'uview-new' : 'uview-other';
            }),
          ],
        );
        addTearDown(container.dispose);
        await container.read(accountProvider.future);
        final result = container.read(ledgerAccountDuplicateCheckerProvider)(
          'uview-new',
        );
        if (sameUfvk) {
          await expectLater(
            result,
            throwsA(isA<LedgerDuplicateAccountException>()),
          );
        } else {
          await result;
        }
      },
    );
  }
}

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/welcome',
  initialAccountState: const AccountState(),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: false,
  isUnlocked: false,
  passwordRotationRecoveryFailed: false,
);

class _UnusedBleService implements LedgerMobileBleService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected BLE call: ${invocation.memberName}');
}

class _CapturingAccountNotifier extends AccountNotifier {
  _CapturingAccountNotifier([this.initial = const AccountState()]);
  final AccountState initial;
  String? importedUfvk;
  int? importedIndex;
  List<int>? importedSeedFingerprint;
  LedgerConnectionTransport? importedTransport;
  String? importedDeviceId;
  String? importedDeviceName;
  String? importedDeviceModel;

  @override
  FutureOr<AccountState> build() => initial;

  @override
  Future<void> importLedgerAccount({
    required String name,
    required String ufvk,
    required List<int> seedFingerprint,
    required int zip32Index,
    required int birthdayHeight,
    String profilePictureId = kDefaultProfilePictureId,
    LedgerConnectionTransport? connectionTransport,
    String? ledgerDeviceId,
    String? ledgerDeviceName,
    String? ledgerDeviceModel,
  }) async {
    importedUfvk = ufvk;
    importedIndex = zip32Index;
    importedSeedFingerprint = seedFingerprint;
    importedTransport = connectionTransport;
    importedDeviceId = ledgerDeviceId;
    importedDeviceName = ledgerDeviceName;
    importedDeviceModel = ledgerDeviceModel;
  }
}

class _RecordingSecurityNotifier extends AppSecurityNotifier {
  _RecordingSecurityNotifier(this.events);
  final List<String> events;

  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: false);

  @override
  Future<void> preparePasswordSetup(String password) async {
    events.add('prepare');
  }

  @override
  void commitPasswordSetup() => events.add('commit');

  @override
  Future<void> rollbackPasswordSetup() async {
    events.add('rollback');
  }
}
