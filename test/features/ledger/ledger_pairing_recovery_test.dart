import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_bluetooth_access.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_request.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_operation_lifecycle.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_pairing_recovery_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_access_recovery_modal.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';

const account = AccountInfo(
  uuid: 'a',
  name: 'Ledger',
  order: 0,
  isHardware: true,
  hardwareSignerKind: HardwareSignerKind.ledger,
  zip32AccountIndex: 3,
  ledgerDeviceId: 'old',
  ledgerDeviceModel: 'Flex',
);
const device = LedgerBleDevice(id: 'new', name: 'Ledger Flex', model: 'Flex');
LedgerDeviceAccount exported([String key = 'expected', int index = 3]) =>
    LedgerDeviceAccount(
      ufvk: key,
      seedFingerprint: const [],
      accountIndex: index,
      appVersion: '1',
    );

class FakeAccounts extends AccountNotifier {
  FakeAccounts({this.initial = account, this.failSave = false});
  final AccountInfo initial;
  final bool failSave;
  int writes = 0;
  String? savedId;
  void changeActive(String uuid) => state = AsyncData(
    AccountState(accounts: [initial], activeAccountUuid: uuid),
  );
  @override
  AccountState build() =>
      AccountState(accounts: [initial], activeAccountUuid: 'a');
  @override
  Future<void> recordLedgerConnection({
    required String uuid,
    required LedgerConnectionTransport transport,
    String? deviceId,
    String? deviceName,
    String? deviceModel,
  }) async {
    if (failSave) throw StateError('Storage failed');
    writes++;
    savedId = deviceId;
    state = AsyncData(
      AccountState(
        accounts: [
          initial.copyWith(
            ledgerDeviceId: deviceId,
            ledgerLastTransport: transport,
          ),
        ],
        activeAccountUuid: 'a',
      ),
    );
  }
}

class FakeSecurity extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
  void setUnlocked(bool value) => state = state.copyWith(isUnlocked: value);
}

class FakeBle
    implements
        LedgerMobileBleService,
        LedgerBluetoothAccess,
        LedgerBluetoothPairingSettings {
  final calls = <String>[];
  LedgerBluetoothAccessStatus access = const LedgerBluetoothAccessStatus(
    LedgerBluetoothPermission.granted,
  );
  List<LedgerBleDevice> devices = [device];
  Future<void>? readinessGate;
  @override
  Future<LedgerMobileAppInfo> currentApp() async {
    calls.add('ready');
    await readinessGate;
    return const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.3');
  }

  bool failDiscovery = false;
  @override
  String? connectedDeviceId;
  @override
  Future<void> stopDiscovery() async {
    calls.add('stop');
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    connectedDeviceId = null;
  }

  @override
  Future<void> connect(LedgerBleDevice device) async {
    calls.add('connect');
    connectedDeviceId = device.id;
  }

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() async* {
    calls.add('scan');
    if (failDiscovery) {
      yield const LedgerDiscoveryFailed(
        LedgerMobileException(LedgerMobileFailure.disconnected, 'Disconnected'),
      );
    }
    yield LedgerDevicesDiscovered(devices);
    yield const LedgerDiscoveryEnded();
  }

  @override
  Future<LedgerBluetoothAccessStatus> bluetoothAccessStatus() async => access;
  @override
  Future<bool> openBluetoothPairingSettings() async {
    calls.add('settings');
    return true;
  }

  @override
  Future<bool> openBluetoothSettings() async => true;
  @override
  Future<void> cancelSigning() async {
    calls.add('cancel');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName}');
}

ProviderContainer containerFor(
  FakeBle ble,
  FakeAccounts accounts, {
  Future<LedgerDeviceAccount> Function()? export,
  TargetPlatform platform = TargetPlatform.macOS,
}) => ProviderContainer(
  overrides: [
    rpcEndpointProvider.overrideWith(FakeRpc.new),
    ledgerMobileBleServiceProvider.overrideWithValue(ble),
    appSecurityProvider.overrideWith(FakeSecurity.new),
    accountProvider.overrideWith(() => accounts),
    ledgerTargetPlatformProvider.overrideWithValue(platform),
    ledgerRecoveryAccountKeyLoaderProvider.overrideWithValue(
      (_) async => 'expected',
    ),
    ledgerBluetoothAccountConnectorProvider.overrideWithValue((index, d) async {
      expect(index, 3);
      expect(d.id, 'new');
      return export == null ? exported() : await export();
    }),
    ledgerRustOperationCancellerProvider.overrideWithValue(() async {}),
  ],
);
void main() {
  for (final failure in ['cancel', 'readiness']) {
    test('saved device $failure does not export or save', () async {
      final pending = Completer<void>();
      final ble = FakeBle()..readinessGate = pending.future;
      final accounts = FakeAccounts(
        initial: account.copyWith(ledgerDeviceId: 'new'),
      );
      var exports = 0;
      final c = containerFor(
        ble,
        accounts,
        export: () async {
          exports++;
          return exported();
        },
      );
      addTearDown(c.dispose);
      final operation = c
          .read(ledgerPairingRecoveryServiceProvider)
          .verifyAndSave(
            accountUuid: 'a',
            device: device,
            checkCurrent: () {},
            onSaving: () => fail('Saved device must not enter persistence'),
          );
      final assertion = expectLater(operation, throwsA(anything));
      await Future<void>.delayed(Duration.zero);
      expect(ble.calls, contains('ready'));
      if (failure == 'cancel') {
        c.read(ledgerDeviceRequestsProvider).cancel();
        pending.complete();
      } else {
        pending.completeError(StateError('Device disconnected'));
      }
      await assertion;
      expect(exports, 0);
      expect(accounts.writes, 0);
    });
  }
  for (final key in ['expected', 'wrong']) {
    test('only matching UFVK commits connection: $key', () async {
      final ble = FakeBle();
      final accounts = FakeAccounts();
      final c = containerFor(ble, accounts, export: () async => exported(key));
      addTearDown(c.dispose);
      final result = c
          .read(ledgerPairingRecoveryServiceProvider)
          .verifyAndSave(
            accountUuid: 'a',
            device: device,
            checkCurrent: () {},
            onSaving: () {},
          );
      if (key == 'wrong') {
        await expectLater(
          result,
          throwsA(isA<LedgerAccountMismatchException>()),
        );
      } else {
        await result;
      }
      expect(accounts.writes, key == 'expected' ? 1 : 0);
      expect(ble.calls, ['stop', 'disconnect', 'connect']);
    });
  }
  test(
    'different account index cannot commit even with matching key',
    () async {
      final accounts = FakeAccounts();
      final c = containerFor(
        FakeBle(),
        accounts,
        export: () async => exported('expected', 4),
      );
      addTearDown(c.dispose);
      await expectLater(
        c
            .read(ledgerPairingRecoveryServiceProvider)
            .verifyAndSave(
              accountUuid: 'a',
              device: device,
              checkCurrent: () {},
              onSaving: () {},
            ),
        throwsA(isA<LedgerAccountMismatchException>()),
      );
      expect(accounts.writes, 0);
    },
  );
  test(
    'cancel during export prevents write and concurrent operation is excluded',
    () async {
      final pending = Completer<LedgerDeviceAccount>();
      final accounts = FakeAccounts();
      final c = containerFor(FakeBle(), accounts, export: () => pending.future);
      addTearDown(c.dispose);
      final operation = c
          .read(ledgerPairingRecoveryServiceProvider)
          .verifyAndSave(
            accountUuid: 'a',
            device: device,
            checkCurrent: () {},
            onSaving: () {},
          );
      final assertion = expectLater(
        operation,
        throwsA(isA<LedgerMobileException>()),
      );
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        c.read(ledgerConnectionServiceProvider).recover(() async {}),
        throwsA(isA<LedgerMobileException>()),
      );
      c.read(ledgerDeviceRequestsProvider).cancel();
      pending.complete(exported());
      await assertion;
      expect(accounts.writes, 0);
    },
  );
  test('destructive pause prevents commit after approval', () async {
    final pending = Completer<LedgerDeviceAccount>();
    final accounts = FakeAccounts();
    final c = containerFor(FakeBle(), accounts, export: () => pending.future);
    addTearDown(c.dispose);
    final op = c
        .read(ledgerPairingRecoveryServiceProvider)
        .verifyAndSave(
          accountUuid: 'a',
          device: device,
          checkCurrent: () {},
          onSaving: () {},
        );
    final assertion = expectLater(op, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await c.read(ledgerOperationLifecycleProvider).quiesceAndDrain();
    pending.complete(exported());
    await assertion;
    expect(accounts.writes, 0);
  });
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets('$platform disclosure and verified reconnect never auto-sign', (
      tester,
    ) async {
      final ble = FakeBle();
      final accounts = FakeAccounts();
      final c = containerFor(ble, accounts, platform: platform);
      addTearDown(c.dispose);
      var retries = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: Center(
                child: LedgerAccessRecoveryModal(
                  account: account,
                  pairingRecovery: true,
                  onRetry: () => retries++,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove the old pairing'), findsNothing);
      await tester.tap(find.text('Did you reset pairing?'));
      await tester.pumpAndSettle();
      expect(find.text('Remove the old pairing'), findsOneWidget);
      expect(
        find.text('Open settings'),
        platform == TargetPlatform.iOS ? findsNothing : findsOneWidget,
      );
      if (platform != TargetPlatform.iOS) {
        await tester.ensureVisible(find.text('Open settings'));
        await tester.tap(find.text('Open settings'));
        await tester.pumpAndSettle();
        expect(ble.calls, ['settings']);
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(retries, 0);
      await tester.ensureVisible(find.text('Find my Ledger'));
      await tester.tap(find.text('Find my Ledger'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ledger Flex'));
      await tester.pumpAndSettle();
      expect(find.text('Your Ledger is connected'), findsOneWidget);
      expect(accounts.savedId, 'new');
      expect(retries, 0);
      await tester.tap(find.text('Continue signing'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('dismissed verification cannot persist late approval', (
    tester,
  ) async {
    final pending = Completer<LedgerDeviceAccount>();
    final accounts = FakeAccounts();
    final ble = FakeBle();
    final c = containerFor(ble, accounts, export: () => pending.future);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: Center(
              child: LedgerAccessRecoveryModal(
                account: account,
                pairingRecovery: true,
                onRetry: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find my Ledger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ledger Flex'));
    await tester.pumpAndSettle();
    expect(find.text('Check your Ledger'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pending.complete(exported());
    await tester.pumpAndSettle();
    expect(accounts.writes, 0);
    expect(ble.calls, contains('cancel'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('queued discovery results cannot replace failure', (
    tester,
  ) async {
    final ble = FakeBle()..failDiscovery = true;
    final accounts = FakeAccounts();
    final c = containerFor(ble, accounts);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: Center(
              child: LedgerAccessRecoveryModal(
                account: account,
                pairingRecovery: true,
                onRetry: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find my Ledger'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t connect to your Ledger'), findsOneWidget);
    expect(find.text('Ledger Flex'), findsNothing);
    expect(accounts.writes, 0);
  });
  for (final change in ['account', 'lock']) {
    test('intermediate $change change invalidates late verification', () async {
      final pending = Completer<LedgerDeviceAccount>();
      final accounts = FakeAccounts();
      final c = containerFor(FakeBle(), accounts, export: () => pending.future);
      addTearDown(c.dispose);
      final op = c
          .read(ledgerPairingRecoveryServiceProvider)
          .verifyAndSave(
            accountUuid: 'a',
            device: device,
            checkCurrent: () {},
            onSaving: () {},
          );
      final assertion = expectLater(op, throwsA(isA<LedgerMobileException>()));
      await Future<void>.delayed(Duration.zero);
      if (change == 'account') {
        accounts.changeActive('other');
        await Future<void>.delayed(Duration.zero);
        accounts.changeActive('a');
      } else {
        final security = c.read(appSecurityProvider.notifier) as FakeSecurity;
        security.setUnlocked(false);
        await Future<void>.delayed(Duration.zero);
        security.setUnlocked(true);
      }
      pending.complete(exported());
      await assertion;
      expect(accounts.writes, 0);
    });
  }
  for (final scenario in ['empty', 'permission', 'radio', 'mismatch']) {
    testWidgets('recovery handles $scenario without signing or saving', (
      tester,
    ) async {
      final ble = FakeBle();
      if (scenario == 'empty') ble.devices = [];
      if (scenario == 'permission') {
        ble.access = const LedgerBluetoothAccessStatus(
          LedgerBluetoothPermission.settings,
        );
      }
      if (scenario == 'radio') {
        ble.access = const LedgerBluetoothAccessStatus(
          LedgerBluetoothPermission.granted,
          bluetoothEnabled: false,
        );
      }
      final accounts = FakeAccounts();
      final c = containerFor(
        ble,
        accounts,
        export: () async => exported('other'),
      );
      addTearDown(c.dispose);
      var retries = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: Center(
                child: LedgerAccessRecoveryModal(
                  account: account,
                  pairingRecovery: true,
                  onRetry: () => retries++,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find my Ledger'));
      await tester.pumpAndSettle();
      if (scenario == 'mismatch') {
        await tester.tap(find.text('Ledger Flex'));
        await tester.pumpAndSettle();
      }
      expect(
        find.text(switch (scenario) {
          'empty' => 'No Ledger devices found',
          'permission' => 'Open settings',
          'radio' => 'Turn on Bluetooth',
          _ => 'This Ledger doesn’t match',
        }),
        findsOneWidget,
      );
      expect(accounts.writes, 0);
      expect(retries, 0);
      expect(tester.takeException(), isNull);
    });
  }
  for (final savedId in ['new', 'old', null, '']) {
    for (final outcome in ['match', 'mismatch', 'save failure']) {
      testWidgets(
        'device hint $savedId / $outcome preserves verification boundary',
        (tester) async {
          final initial = AccountInfo(
            uuid: 'a',
            name: 'Ledger',
            order: 0,
            isHardware: true,
            hardwareSignerKind: HardwareSignerKind.ledger,
            zip32AccountIndex: 3,
            ledgerDeviceId: savedId,
            ledgerDeviceModel: 'Flex',
          );
          final ble = FakeBle();
          final accounts = FakeAccounts(
            initial: initial,
            failSave: outcome == 'save failure',
          );
          var checks = 0;
          final c = containerFor(
            ble,
            accounts,
            export: () async {
              checks++;
              return exported(outcome == 'mismatch' ? 'other' : 'expected');
            },
          );
          addTearDown(c.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: c,
              child: MaterialApp(
                home: AppTheme(
                  data: AppThemeData.light,
                  child: Center(
                    child: LedgerAccessRecoveryModal(
                      account: initial,
                      pairingRecovery: true,
                      onRetry: () {},
                      onClose: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Find my Ledger'));
          await tester.pumpAndSettle();
          expect(
            find.text('Different from saved connection'),
            savedId == 'old' ? findsOneWidget : findsNothing,
          );
          expect(checks, 0);
          expect(ble.calls, isNot(contains('connect')));
          await tester.tap(find.text('Ledger Flex'));
          await tester.pumpAndSettle();
          expect(checks, savedId == 'new' ? 0 : 1);
          expect(
            accounts.writes,
            savedId != 'new' && outcome == 'match' ? 1 : 0,
          );
          expect(
            find.textContaining('saved connection has been updated'),
            outcome == 'match' && savedId == 'old'
                ? findsOneWidget
                : findsNothing,
          );
          if (outcome == 'match' || savedId == 'new') {
            expect(accounts.savedId, savedId == 'new' ? isNull : 'new');
            expect(find.text('Your Ledger is connected'), findsOneWidget);
          } else {
            expect(
              c.read(accountProvider).value!.accounts.single.ledgerDeviceId,
              savedId,
            );
            expect(find.text('Your Ledger is connected'), findsNothing);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

class FakeRpc extends RpcEndpointNotifier {
  @override
  RpcEndpointConfig build() => defaultRpcEndpointConfig("main");
}
