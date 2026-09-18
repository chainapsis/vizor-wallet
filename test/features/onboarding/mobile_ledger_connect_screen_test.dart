@Tags(['mobile'])
library;

import 'dart:async';
import 'package:zcash_wallet/src/features/ledger/services/ledger_failure_guidance.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_ledger_connect_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_ledger_device_sheet.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_method_selection_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_setup_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart' as rust_ledger;

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1;
  });

  group('mobile method selection Ledger visibility', () {
    testWidgets('shows Ledger for iOS and Android mainnet software wallets', (
      tester,
    ) async {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        await tester.pumpWidget(
          _methodHarness(
            bootstrap: _bootstrap(
              accounts: const [
                AccountInfo(uuid: 'software', name: 'Main', order: 0),
              ],
            ),
            platform: platform,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Connect Ledger'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('mobile_welcome_ledger')),
          findsOneWidget,
        );
      }
    });

    testWidgets('shows Ledger for an existing Keystone-only wallet', (
      tester,
    ) async {
      await tester.pumpWidget(
        _methodHarness(
          bootstrap: _bootstrap(
            accounts: const [
              AccountInfo(
                uuid: 'hardware',
                name: 'Hardware',
                order: 0,
                isHardware: true,
              ),
            ],
          ),
          platform: TargetPlatform.android,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect Ledger'), findsOneWidget);
    });

    testWidgets('shows Ledger for first-run or unconfigured wallets', (
      tester,
    ) async {
      for (final bootstrap in [
        _bootstrap(accounts: const []),
        _bootstrap(
          accounts: const [
            AccountInfo(uuid: 'software', name: 'Main', order: 0),
          ],
          passwordConfigured: false,
        ),
      ]) {
        await tester.pumpWidget(
          _methodHarness(
            bootstrap: bootstrap,
            platform: TargetPlatform.android,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Connect Ledger'), findsOneWidget);
      }
    });

    testWidgets('hides Ledger on unsupported platforms and testnet', (
      tester,
    ) async {
      const account = AccountInfo(uuid: 'software', name: 'Main', order: 0);
      await tester.pumpWidget(
        _methodHarness(
          bootstrap: _bootstrap(accounts: const [account]),
          platform: TargetPlatform.windows,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect Ledger'), findsNothing);

      await tester.pumpWidget(
        _methodHarness(
          bootstrap: _bootstrap(accounts: const [account], network: 'test'),
          platform: TargetPlatform.android,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect Ledger'), findsNothing);
    });
  });

  test('mobile onboarding registers the guarded Ledger routes', () {
    final paths = mobileOnboardingRoutes().whereType<GoRoute>().map(
      (route) => route.path,
    );
    expect(
      paths,
      containsAll([
        '/onboarding/ledger',
        '/onboarding/ledger/birthday',
        '/onboarding/ledger/customise-account',
      ]),
    );
    for (final route in mobileOnboardingRoutes().whereType<GoRoute>().where(
      (route) => route.path.startsWith('/onboarding/ledger/'),
    )) {
      expect(route.redirect, isNotNull);
    }
  });

  for (final guardedPath in const [
    '/onboarding/ledger/birthday',
    '/onboarding/ledger/customise-account',
  ]) {
    testWidgets('$guardedPath redirects to connect without route extra', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: guardedPath,
        routes: mobileOnboardingRoutes(),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWithValue(
              _bootstrap(
                accounts: const [
                  AccountInfo(uuid: 'software', name: 'Main', order: 0),
                ],
              ),
            ),
            ledgerMobileBleServiceProvider.overrideWithValue(_FakeBleService()),
            ledgerOperationCancellerProvider.overrideWithValue(() async {}),
            ledgerAppReadinessStateProvider.overrideWith(
              _FakeReadinessController.new,
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.light, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connect Ledger'), findsOneWidget);
    });
  }

  for (final scenario in ['fresh', 'unconfigured', 'locked']) {
    final bootstrap = _bootstrap(
      accounts: scenario == 'fresh'
          ? const []
          : const [AccountInfo(uuid: 'software', name: 'Main', order: 0)],
      passwordConfigured: scenario == 'locked',
      unlocked: scenario != 'locked',
    );
    for (final route in mobileOnboardingRoutes().whereType<GoRoute>().where(
      (route) =>
          scenario == 'locked' && route.path.startsWith('/onboarding/ledger'),
    )) {
      testWidgets('${route.path} rejects $scenario wallet with valid extras', (
        tester,
      ) async {
        const account = LedgerDeviceAccount(
          ufvk: 'test-ufvk',
          seedFingerprint: [1],
          accountIndex: 0,
          appVersion: '1',
        );
        final router = GoRouter(
          initialLocation: route.path,
          initialExtra: route.path.endsWith('/birthday')
              ? const LedgerBirthdayArgs(account: account)
              : const LedgerCustomiseAccountArgs(
                  account: account,
                  birthdayHeight: 1,
                ),
          routes: [
            route,
            GoRoute(
              path: '/welcome',
              builder: (_, _) => const Text('setup-required'),
            ),
            GoRoute(
              path: '/unlock',
              builder: (_, _) => const Text('unlock-required'),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(scenario == 'fresh' ? 'setup-required' : 'unlock-required'),
          findsOneWidget,
        );
      });
    }
    test(
      'Ledger import rejects $scenario wallet before storage or Rust access',
      () async {
        final container = ProviderContainer(
          overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
        );
        addTearDown(container.dispose);
        await container.read(accountProvider.future);
        await expectLater(
          container
              .read(accountProvider.notifier)
              .importLedgerAccount(
                name: 'Ledger',
                ufvk: 'test-ufvk',
                seedFingerprint: [1],
                zip32Index: 0,
                birthdayHeight: 1,
              ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Set up and unlock your wallet before adding a Ledger account.',
            ),
          ),
        );
        expect(
          container.read(accountProvider).requireValue.accounts.length,
          bootstrap.initialAccountState.accounts.length,
        );
      },
    );
  }

  testWidgets('discovers, connects, and exports the selected Ledger', (
    tester,
  ) async {
    final ble = _FakeBleService(failCleanupStopsAfter: 2);
    final accountApproval = Completer<LedgerDeviceAccount>();
    var connectorCalls = 0;
    int? requestedIndex;

    await tester.pumpWidget(
      _ledgerHarness(
        ble: ble,
        connector: (index) async {
          connectorCalls++;
          requestedIndex = index;
          return accountApproval.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    final importButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_ledger_import_button')),
    );
    expect(importButton.onPressed, isNull);
    expect(connectorCalls, 0);

    await tester.tap(
      find.byKey(const ValueKey('mobile_ledger_select_device_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    ble.emit(
      const LedgerDevicesDiscovered([
        LedgerBleDevice(id: 'nano-x', name: 'Rowan Ledger', model: 'Nano X'),
      ]),
    );
    await tester.pump();

    final deviceRow = find.byKey(const ValueKey('mobile_ledger_device_nano-x'));
    expect(deviceRow, findsOneWidget);
    expect(tester.getSize(deviceRow).height, greaterThanOrEqualTo(44));
    await tester.tap(find.text('Ledger Nano X · Rowan Ledger'));
    await tester.pump();
    expect(
      find.text('Connecting to Ledger Nano X · Rowan Ledger'),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(ble.connectedIds, ['nano-x']);
    expect(find.text('Ledger Nano X · Rowan Ledger'), findsOneWidget);

    final advanced = find.byKey(
      const ValueKey('mobile_ledger_advanced_options_disclosure'),
    );
    await tester.ensureVisible(advanced);
    await tester.tap(advanced);
    await tester.pumpAndSettle();
    for (final invalid in ['101', '', '999999999999999999999999']) {
      await tester.enterText(
        find.byKey(const ValueKey('mobile_ledger_account_index_field')),
        invalid,
      );
      final submit = find.byKey(const ValueKey('mobile_ledger_import_button'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(
        find.text('Account index must be between 0 and 100.'),
        findsOneWidget,
      );
      expect(connectorCalls, 0);
    }
    await tester.enterText(
      find.byKey(const ValueKey('mobile_ledger_account_index_field')),
      '100',
    );
    final enabledImport = find.byKey(
      const ValueKey('mobile_ledger_import_button'),
    );
    await tester.ensureVisible(enabledImport);
    await tester.tap(enabledImport);
    await tester.pump();

    final busyImport = tester.widget<AppButton>(enabledImport);
    final spinner = find.byKey(const ValueKey('mobile_ledger_import_spinner'));
    expect(busyImport.leading, isNull);
    expect(busyImport.trailing, isA<AppIcon>());
    expect((busyImport.trailing! as AppIcon).name, AppIcons.loader);
    expect(spinner, findsOneWidget);
    expect(
      tester.getCenter(spinner).dx,
      greaterThan(tester.getCenter(enabledImport).dx),
    );

    accountApproval.complete(
      const LedgerDeviceAccount(
        ufvk: 'uview-100',
        seedFingerprint: [1, 2, 3],
        accountIndex: 100,
        appVersion: '3.9.3',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('birthday-route-bluetooth-Nano X'), findsOneWidget);
    expect(connectorCalls, 1);
    expect(requestedIndex, 100);
    expect(
      find.byKey(const ValueKey('mobile_ledger_account_name_field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mobile_ledger_birthday_height_field')),
      findsNothing,
    );
    expect(ble.stopCalls, greaterThanOrEqualTo(1));
  });

  for (final failure in [
    LedgerMobileFailure.pairingInvalid,
    LedgerMobileFailure.permissionDenied,
    LedgerMobileFailure.locationDisabled,
  ]) {
    testWidgets('picker retains devices and shows $failure with retry', (
      tester,
    ) async {
      final ble = _FakeBleService();
      await tester.pumpWidget(
        AppTheme(
          data: AppThemeData.light,
          child: MaterialApp(
            home: MobileLedgerDeviceSheet(
              service: ble,
              onSelected: (_) {},
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      const device = LedgerBleDevice(
        id: 'recovery-device',
        name: 'Recovery Ledger',
        model: 'Nano X',
      );
      ble.emit(const LedgerDevicesDiscovered([device]));
      await tester.pump();
      final error = LedgerMobileException(failure, 'native diagnostic');
      final connection = Completer<void>();
      ble.pendingConnect = connection.future;
      await tester.tap(find.text('Ledger Nano X · Recovery Ledger'));
      await tester.pump();
      connection.completeError(error);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ledger Nano X · Recovery Ledger'), findsOneWidget);
      expect(find.text(ledgerFailureGuidance(error)!.message), findsOneWidget);
      ble.pendingConnect = null;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(ledgerFailureGuidance(error)!.message), findsNothing);
    });
  }

  testWidgets('shows permission, Bluetooth, empty, and retry states', (
    tester,
  ) async {
    final ble = _FakeBleService(permissionResults: [false, true, true]);
    await tester.pumpWidget(
      _ledgerHarness(
        ble: ble,
        connector: (_) => throw StateError('must not import'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_ledger_select_device_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('Bluetooth permission is required'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    ble.emit(
      const LedgerDiscoveryFailed(
        LedgerMobileException(
          LedgerMobileFailure.bluetoothOff,
          'Bluetooth disabled',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Turn on Bluetooth, then try again.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    ble.emit(const LedgerDiscoveryEnded());
    await tester.pump();
    expect(find.text('No Ledger devices found'), findsOneWidget);
    expect(ble.permissionCalls, 3);
  });

  for (final stage in ['stopDiscovery', 'connect']) {
    testWidgets(
      'closing picker during $stage cancels without selecting a late device',
      (tester) async {
        final ble = _FakeBleService();
        var selections = 0;
        var closes = 0;
        await tester.pumpWidget(
          AppTheme(
            data: AppThemeData.light,
            child: MaterialApp(
              home: MobileLedgerDeviceSheet(
                service: ble,
                onSelected: (_) => selections++,
                onClose: () => closes++,
              ),
            ),
          ),
        );
        await tester.pump();
        ble.emit(
          const LedgerDevicesDiscovered([
            LedgerBleDevice(id: 'stax', name: 'Rowan Ledger', model: 'Stax'),
          ]),
        );
        await tester.pump();
        final pending = Completer<void>();
        if (stage == 'connect') {
          ble.pendingConnect = pending.future;
        } else {
          ble.pendingStop = pending.future;
        }
        await tester.tap(find.text('Ledger Stax · Rowan Ledger'));
        await tester.pump();
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pump();
        expect(closes, 1);
        expect(ble.cancelCalls, 1);
        pending.complete();
        await tester.pump();
        expect(selections, 0);
        if (stage == 'stopDiscovery') expect(ble.connectedIds, isEmpty);
        await tester.pumpWidget(const SizedBox());
        expect(ble.cancelCalls, 1);
      },
    );
  }

  testWidgets(
    'disposing picker while initial discovery stops cannot disconnect a later session',
    (tester) async {
      final pending = Completer<void>();
      final ble = _FakeBleService()..pendingStop = pending.future;
      await tester.pumpWidget(
        AppTheme(
          data: AppThemeData.light,
          child: MaterialApp(
            home: MobileLedgerDeviceSheet(
              service: ble,
              onSelected: (_) {},
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pump();
      expect(ble.disconnectCalls, 0);
      expect(ble.permissionCalls, 0);
    },
  );

  testWidgets(
    'route dismissal cancels before the picker exit animation finishes',
    (tester) async {
      final pending = Completer<void>();
      final ble = _FakeBleService()..pendingConnect = pending.future;
      await tester.pumpWidget(
        _ledgerHarness(ble: ble, connector: (_) => throw StateError('unused')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('mobile_ledger_select_device_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      ble.emit(
        const LedgerDevicesDiscovered([
          LedgerBleDevice(id: 'stax', name: 'Rowan Ledger', model: 'Stax'),
        ]),
      );
      await tester.pump();
      await tester.tap(find.text('Ledger Stax · Rowan Ledger'));
      await tester.pump();
      Navigator.of(tester.element(find.byType(MobileLedgerDeviceSheet))).pop();
      expect(ble.cancelCalls, 1);
      pending.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MobileLedgerDeviceSheet), findsNothing);
      expect(find.byType(MobileLedgerConnectScreen), findsOneWidget);
      expect(ble.cancelCalls, 1);
    },
  );

  testWidgets('stops discovery when the device sheet closes', (tester) async {
    final ble = _FakeBleService();
    await tester.pumpWidget(
      _ledgerHarness(ble: ble, connector: (_) => throw StateError('unused')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_ledger_select_device_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('mobile_ledger_device_sheet')),
      findsNothing,
    );
    expect(ble.stopCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('disconnects the retained session before rediscovering', (
    tester,
  ) async {
    final ble = _FakeBleService();
    await tester.pumpWidget(
      _ledgerHarness(ble: ble, connector: (_) => throw StateError('unused')),
    );
    await tester.pumpAndSettle();

    Future<void> openPickerAndDiscover() async {
      await tester.tap(
        find.byKey(const ValueKey('mobile_ledger_select_device_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      ble.emit(
        const LedgerDevicesDiscovered([
          LedgerBleDevice(id: 'stax', name: 'Rowan Ledger', model: 'Stax'),
        ]),
      );
      await tester.pump();
    }

    await openPickerAndDiscover();
    expect(ble.calls.take(4), [
      'stopDiscovery',
      'disconnect',
      'requestPermissions',
      'discoverDevices',
    ]);
    await tester.tap(find.text('Ledger Stax · Rowan Ledger'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ble.connectedIds, ['stax']);
    expect(ble.cancelCalls, 0);

    await openPickerAndDiscover();
    expect(
      find.byKey(const ValueKey('mobile_ledger_device_stax')),
      findsOneWidget,
    );
    expect(ble.disconnectCalls, 2);
  });
}

Widget _methodHarness({
  required AppBootstrapState bootstrap,
  required TargetPlatform platform,
}) => ProviderScope(
  key: ValueKey(platform),
  overrides: [
    appBootstrapProvider.overrideWithValue(bootstrap),
    ledgerTargetPlatformProvider.overrideWithValue(platform),
  ],
  child: AppTheme(
    data: AppThemeData.light,
    child: const MaterialApp(home: MobileMethodSelectionScreen()),
  ),
);

Widget _ledgerHarness({
  required _FakeBleService ble,
  required LedgerAccountConnector connector,
}) {
  final router = GoRouter(
    initialLocation: '/onboarding/ledger',
    routes: [
      GoRoute(
        path: '/onboarding/ledger',
        builder: (_, _) => const MobileLedgerConnectScreen(),
      ),
      GoRoute(
        path: '/onboarding/ledger/birthday',
        builder: (_, state) {
          final args = state.extra! as LedgerBirthdayArgs;
          return Text(
            'birthday-route-${args.account.transport.name}-${args.account.device?.model}',
            key: ValueKey(args.account.accountIndex),
          );
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(
          accounts: const [
            AccountInfo(uuid: 'software', name: 'Main', order: 0),
          ],
        ),
      ),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
      ledgerMobileBleServiceProvider.overrideWithValue(ble),
      ledgerBluetoothAccountConnectorProvider.overrideWithValue((
        accountIndex,
        device,
      ) async {
        final account = await connector(accountIndex);
        return LedgerDeviceAccount(
          ufvk: account.ufvk,
          seedFingerprint: account.seedFingerprint,
          accountIndex: account.accountIndex,
          appVersion: account.appVersion,
          transport: LedgerConnectionTransport.bluetooth,
          device: device,
        );
      }),
      ledgerOperationCancellerProvider.overrideWithValue(() async {}),
      ledgerAppReadinessStateProvider.overrideWith(
        _FakeReadinessController.new,
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

AppBootstrapState _bootstrap({
  required List<AccountInfo> accounts,
  bool passwordConfigured = true,
  bool unlocked = true,
  String network = 'main',
}) => AppBootstrapState(
  initialLocation: '/onboarding/method',
  initialAccountState: AccountState(accounts: accounts),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: network,
  rpcEndpointConfig: defaultRpcEndpointConfig(network),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: passwordConfigured,
  isUnlocked: unlocked,
  passwordRotationRecoveryFailed: false,
);

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(chainTipHeight: 4000000);
}

class _FakeReadinessController extends LedgerAppReadinessController {
  @override
  LedgerAppReadinessState build() => const LedgerAppReadinessState.idle();
}

class _FakeBleService implements LedgerMobileBleService {
  _FakeBleService({
    List<bool> permissionResults = const [true],
    this.failCleanupStopsAfter,
  }) : _permissionResults = permissionResults;

  final List<bool> _permissionResults;
  final int? failCleanupStopsAfter;
  final _updates = StreamController<LedgerDiscoveryUpdate>.broadcast(
    sync: true,
  );
  final List<String> connectedIds = [];
  final List<String> calls = [];
  int permissionCalls = 0;
  int stopCalls = 0;
  int disconnectCalls = 0;
  int cancelCalls = 0;
  Future<void>? pendingConnect;
  Future<void>? pendingStop;

  @override
  String? connectedDeviceId;

  void emit(LedgerDiscoveryUpdate update) => _updates.add(update);

  @override
  Future<void> connect(LedgerBleDevice device) async {
    calls.add('connect');
    if (pendingConnect != null) await pendingConnect;
    connectedIds.add(device.id);
    connectedDeviceId = device.id;
  }

  @override
  Future<LedgerMobileAppInfo> currentApp() async =>
      const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.3');

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() {
    calls.add('discoverDevices');
    return _updates.stream;
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    disconnectCalls++;
    connectedDeviceId = null;
  }

  @override
  Future<List<Uint8List>> exchangeUfvk(
    rust_ledger.LedgerUfvkApduPlan plan,
  ) async => const [];

  @override
  Future<List<Uint8List>> exchangeApdus(
    List<rust_ledger.LedgerApduCommand> commands,
  ) async => const [];

  @override
  Future<void> cancelSigning() async {
    cancelCalls++;
  }

  @override
  Future<bool> requestPermissions() async {
    calls.add('requestPermissions');
    final index = permissionCalls++;
    return _permissionResults[index < _permissionResults.length
        ? index
        : _permissionResults.length - 1];
  }

  @override
  Future<LedgerMobileAppInfo> requestOpenZcashApp() async =>
      const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.3');

  @override
  Future<void> stopDiscovery() async {
    calls.add('stopDiscovery');
    stopCalls++;
    if (pendingStop != null) await pendingStop;
    final threshold = failCleanupStopsAfter;
    if (threshold != null && stopCalls > threshold) {
      throw const LedgerMobileException(
        LedgerMobileFailure.unavailable,
        'Cleanup failed.',
      );
    }
  }
}
