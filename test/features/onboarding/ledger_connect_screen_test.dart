import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_text_field.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_connect_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_setup_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart' as rust_ledger;

void main() {
  testWidgets('exports the approved Ledger account and continues setup', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    int? requestedIndex;
    var importCalls = 0;

    await tester.pumpWidget(
      _harness(
        connector: (accountIndex) async {
          requestedIndex = accountIndex;
          return const LedgerDeviceAccount(
            ufvk: 'uview-ledger',
            seedFingerprint: [7, 8, 9],
            accountIndex: 0,
            appVersion: '3.9.1',
          );
        },
        importer:
            ({
              required name,
              required account,
              required birthdayHeight,
              required profilePictureId,
            }) async {
              importCalls++;
            },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect Ledger'), findsWidgets);
    expect(
      find.byKey(const ValueKey('ledger_account_index_field')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
    await tester.pumpAndSettle();

    expect(find.text('birthday-uview-ledger'), findsOneWidget);
    expect(requestedIndex, 0);
    expect(importCalls, 0);
  });

  testWidgets('reveals the Ledger account index from advanced options', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _harness(
        connector: (_) async => const LedgerDeviceAccount(
          ufvk: 'unused',
          seedFingerprint: [1],
          accountIndex: 0,
          appVersion: '3.9.1',
        ),
        importer:
            ({
              required name,
              required account,
              required birthdayHeight,
              required profilePictureId,
            }) async {},
      ),
    );
    await tester.pumpAndSettle();

    final disclosure = find.byKey(
      const ValueKey('ledger_advanced_options_disclosure'),
    );
    expect(
      tester.getSemantics(disclosure),
      isSemantics(
        label: 'Advanced options',
        isButton: true,
        isEnabled: true,
        isExpanded: false,
        hasTapAction: true,
      ),
    );
    expect(
      find.byKey(const ValueKey('ledger_account_index_field')),
      findsNothing,
    );

    await tester.tap(disclosure);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ledger_account_index_field')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(disclosure),
      isSemantics(
        label: 'Advanced options',
        isButton: true,
        isEnabled: true,
        isExpanded: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('submits a custom revealed Ledger account index', (tester) async {
    await _setDesktopViewport(tester);
    int? requestedIndex;

    await tester.pumpWidget(
      _harness(
        connector: (accountIndex) async {
          requestedIndex = accountIndex;
          return LedgerDeviceAccount(
            ufvk: 'uview-ledger-$accountIndex',
            seedFingerprint: const [7, 8, 9],
            accountIndex: accountIndex,
            appVersion: '3.9.1',
          );
        },
        importer:
            ({
              required name,
              required account,
              required birthdayHeight,
              required profilePictureId,
            }) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('ledger_advanced_options_disclosure')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ledger_account_index_field')),
      '12',
    );
    await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
    await tester.pumpAndSettle();

    expect(find.text('birthday-uview-ledger-12'), findsOneWidget);
    expect(requestedIndex, 12);
  });

  testWidgets(
    'keeps expanded advanced options stable and disabled while busy',
    (tester) async {
      await _setDesktopViewport(tester);
      final semantics = tester.ensureSemantics();
      final pendingAccount = Completer<LedgerDeviceAccount>();

      await tester.pumpWidget(
        _harness(
          connector: (_) => pendingAccount.future,
          importer:
              ({
                required name,
                required account,
                required birthdayHeight,
                required profilePictureId,
              }) async {},
        ),
      );
      await tester.pumpAndSettle();

      final disclosure = find.byKey(
        const ValueKey('ledger_advanced_options_disclosure'),
      );
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
      await tester.pump();

      final busyButton = tester.widget<AppButton>(
        find.byKey(const ValueKey('ledger_connect_button')),
      );
      final spinner = find.byKey(const ValueKey('ledger_connect_spinner'));
      expect(busyButton.leading, isNull);
      expect(busyButton.trailing, isA<AppIcon>());
      expect((busyButton.trailing! as AppIcon).name, AppIcons.loader);
      expect(spinner, findsOneWidget);
      expect(
        tester.getCenter(spinner).dx,
        greaterThan(tester.getCenter(find.text('Approve on Ledger')).dx),
      );

      expect(
        tester.getSemantics(disclosure),
        isSemantics(
          label: 'Advanced options',
          isButton: true,
          isEnabled: false,
          isExpanded: true,
          hasTapAction: false,
        ),
      );
      expect(
        tester
            .widget<AppTextField>(
              find.byKey(const ValueKey('ledger_account_index_field')),
            )
            .enabled,
        isFalse,
      );

      pendingAccount.completeError(StateError('request rejected 6985'));
      await tester.pumpAndSettle();
      semantics.dispose();
    },
  );

  testWidgets('shows an actionable device rejection without importing', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    var importCalls = 0;

    await tester.pumpWidget(
      _harness(
        connector: (_) => Future.error(StateError('request rejected 6985')),
        importer:
            ({
              required name,
              required account,
              required birthdayHeight,
              required profilePictureId,
            }) async {
              importCalls++;
            },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('The viewing-key request was rejected on your Ledger.'),
      findsOneWidget,
    );
    expect(importCalls, 0);
    expect(find.text('home-route'), findsNothing);
  });

  testWidgets('keeps the import route while showing the readiness stage', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final pendingAccount = Completer<LedgerDeviceAccount>();

    await tester.pumpWidget(
      _harness(
        connector: (_) => pendingAccount.future,
        importer:
            ({
              required name,
              required account,
              required birthdayHeight,
              required profilePictureId,
            }) async {},
        readiness: const LedgerAppReadinessState.inProgress(
          LedgerAppReadinessPhase.checkingDevice,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
    await tester.pump();

    expect(find.text('Checking device'), findsOneWidget);
    expect(find.text('Connect Ledger'), findsWidgets);
    expect(find.text('home-route'), findsNothing);

    pendingAccount.completeError(StateError('request rejected 6985'));
    await tester.pumpAndSettle();
  });

  testWidgets('imports the approved Ledger account over macOS Bluetooth', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final ble = _FakeLedgerBleService();
    LedgerBleDevice? requestedDevice;

    await tester.pumpWidget(
      _harness(
        connector: (_) => Future.error(StateError('USB should not be used')),
        bluetoothConnector: (accountIndex, device) async {
          requestedDevice = device;
          await ble.requestOpenZcashApp();
          return LedgerDeviceAccount(
            ufvk: 'uview-bluetooth',
            seedFingerprint: const [4, 5, 6],
            accountIndex: accountIndex,
            appVersion: '3.9.2',
            transport: LedgerConnectionTransport.bluetooth,
            device: device,
          );
        },
        importer:
            ({
              required name,
              required account,
              required birthdayHeight,
              required profilePictureId,
            }) async {},
        bleService: ble,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('ledger_desktop_ble_connect_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ledger Flex is ready'), findsOneWidget);
    expect(
      find.text('Zcash 3.9.2 approved account 0 over Bluetooth.'),
      findsOneWidget,
    );
    expect(ble.connectedDeviceId, 'ledger-1');
    expect(ble.openAppCalls, 1);
    expect(requestedDevice?.model, 'Ledger Flex');

    await tester.tap(find.byKey(const ValueKey('ledger_desktop_ble_continue')));
    await tester.pumpAndSettle();
    expect(find.text('birthday-uview-bluetooth'), findsOneWidget);
  });

  testWidgets(
    'shows same-wallet accounts, suggests the first gap, and blocks duplicates',
    (tester) async {
      await _setDesktopViewport(tester);
      var connectorCalls = 0;
      const fingerprint =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      await tester.pumpWidget(
        _harness(
          sourceAccountUuid: 'ledger-0',
          accountState: const AccountState(
            accounts: [
              AccountInfo(
                uuid: 'ledger-0',
                name: 'Primary Ledger account',
                order: 0,
                isHardware: true,
                hardwareSignerKind: HardwareSignerKind.ledger,
                zip32AccountIndex: 0,
                ledgerWalletFingerprint: fingerprint,
              ),
              AccountInfo(
                uuid: 'ledger-2',
                name: 'Savings',
                order: 1,
                isHardware: true,
                hardwareSignerKind: HardwareSignerKind.ledger,
                zip32AccountIndex: 2,
                ledgerWalletFingerprint: fingerprint,
              ),
              AccountInfo(
                uuid: 'other-ledger-1',
                name: 'Different Ledger',
                order: 2,
                isHardware: true,
                hardwareSignerKind: HardwareSignerKind.ledger,
                zip32AccountIndex: 1,
                ledgerWalletFingerprint:
                    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              ),
            ],
            activeAccountUuid: 'ledger-0',
          ),
          identityConnector: () async =>
              const LedgerWalletIdentity(fingerprint: fingerprint),
          connector: (_) async {
            connectorCalls++;
            throw StateError('duplicate must stop before device export');
          },
          importer:
              ({
                required name,
                required account,
                required birthdayHeight,
                required profilePictureId,
              }) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Primary Ledger account'), findsOneWidget);
      expect(find.text('Savings'), findsOneWidget);
      expect(find.text('Different Ledger'), findsNothing);
      expect(find.text('Next available index: 1'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('ledger_advanced_options_disclosure')),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<AppTextField>(
        find.byKey(const ValueKey('ledger_account_index_field')),
      );
      expect(field.controller!.text, '1');
      await tester.enterText(
        find.byKey(const ValueKey('ledger_account_index_field')),
        '2',
      );
      await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Index 2 is already used by this Ledger wallet.'),
        findsOneWidget,
      );
      expect(connectorCalls, 0);
    },
  );

  testWidgets('stops a wrong Ledger before requesting the target UFVK', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    var connectorCalls = 0;
    await tester.pumpWidget(
      _harness(
        sourceAccountUuid: 'ledger-0',
        accountState: const AccountState(
          accounts: [
            AccountInfo(
              uuid: 'ledger-0',
              name: 'Primary',
              order: 0,
              isHardware: true,
              hardwareSignerKind: HardwareSignerKind.ledger,
              zip32AccountIndex: 0,
              ledgerWalletFingerprint:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            ),
          ],
          activeAccountUuid: 'ledger-0',
        ),
        identityConnector: () async => const LedgerWalletIdentity(
          fingerprint:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
        connector: (_) async {
          connectorCalls++;
          throw StateError('should not request UFVK');
        },
        importer:
            ({
              required name,
              required account,
              required birthdayHeight,
              required profilePictureId,
            }) async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('This Ledger does not match the account you started from.'),
      findsOneWidget,
    );
    expect(connectorCalls, 0);
  });
}

Widget _harness({
  required LedgerAccountConnector connector,
  required LedgerAccountImporter importer,
  LedgerBluetoothAccountConnector? bluetoothConnector,
  LedgerWalletIdentityConnector? identityConnector,
  LedgerBluetoothWalletIdentityConnector? bluetoothIdentityConnector,
  AccountState accountState = const AccountState(),
  String? sourceAccountUuid,
  LedgerAppReadinessState readiness = const LedgerAppReadinessState.idle(),
  LedgerMobileBleService? bleService,
}) {
  final router = GoRouter(
    initialLocation: '/onboarding/ledger',
    routes: [
      GoRoute(
        path: '/onboarding/ledger',
        builder: (_, _) =>
            LedgerConnectScreen(sourceAccountUuid: sourceAccountUuid),
      ),
      GoRoute(
        path: '/onboarding/ledger/birthday',
        builder: (_, state) {
          final args = state.extra! as LedgerBirthdayArgs;
          return Text('birthday-${args.account.ufvk}');
        },
      ),
      GoRoute(path: '/add-account', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/home', builder: (_, _) => const Text('home-route')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      accountProvider.overrideWith(() => _FakeAccountNotifier(accountState)),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
      ledgerAccountConnectorProvider.overrideWithValue(connector),
      ledgerWalletIdentityConnectorProvider.overrideWithValue(
        identityConnector ??
            () async => const LedgerWalletIdentity(
              fingerprint:
                  '0000000000000000000000000000000000000000000000000000000000000001',
            ),
      ),
      ledgerBluetoothAccountConnectorProvider.overrideWithValue(
        bluetoothConnector ??
            (_, _) => Future.error(StateError('Bluetooth should not be used')),
      ),
      ledgerBluetoothWalletIdentityConnectorProvider.overrideWithValue(
        bluetoothIdentityConnector ??
            (_) async => const LedgerWalletIdentity(
              fingerprint:
                  '0000000000000000000000000000000000000000000000000000000000000001',
            ),
      ),
      ledgerAccountImporterProvider.overrideWithValue(importer),
      ledgerOperationCancellerProvider.overrideWithValue(() async {}),
      if (bleService != null)
        ledgerMobileBleServiceProvider.overrideWithValue(bleService),
      ledgerAppReadinessStateProvider.overrideWith(
        () => _FakeReadinessController(readiness),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(chainTipHeight: 4000000);
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  Future<AccountState> build() async => initialState;
}

class _FakeReadinessController extends LedgerAppReadinessController {
  _FakeReadinessController(this.initialState);

  final LedgerAppReadinessState initialState;

  @override
  LedgerAppReadinessState build() => initialState;
}

class _FakeLedgerBleService implements LedgerMobileBleService {
  @override
  String? connectedDeviceId;
  int disconnectCalls = 0;
  int openAppCalls = 0;

  @override
  Future<void> cancelSigning() async {}

  @override
  Future<void> connect(LedgerBleDevice device) async {
    connectedDeviceId = device.id;
  }

  @override
  Future<LedgerMobileAppInfo> currentApp() async {
    return const LedgerMobileAppInfo(name: 'BOLOS', version: '1.0.0');
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() async* {
    yield const LedgerDevicesDiscovered([
      LedgerBleDevice(
        id: 'ledger-1',
        name: 'Ledger Flex',
        model: 'Ledger Flex',
      ),
    ]);
  }

  @override
  Future<List<Uint8List>> exchangeApdus(
    List<rust_ledger.LedgerApduCommand> commands,
  ) async => const [];

  @override
  Future<List<Uint8List>> exchangeUfvk(
    rust_ledger.LedgerUfvkApduPlan plan,
  ) async => const [];

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<LedgerMobileAppInfo> requestOpenZcashApp() async {
    openAppCalls++;
    return const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.2');
  }

  @override
  Future<void> stopDiscovery() async {}
}
