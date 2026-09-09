@Tags(['mobile'])
library;

import 'dart:async';

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
import 'package:zcash_wallet/src/core/widgets/app_text_field.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_recovery.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_ledger_connect_screen.dart';
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

  for (final mismatch in ['none', 'wallet', 'ufvk']) {
    testWidgets(
      'connects a linked Ledger only after identity checks: $mismatch',
      (tester) async {
        tester.view.physicalSize = const Size(393, 700);
        final ble = _FakeBleService();
        const fingerprint =
            '0000000000000000000000000000000000000000000000000000000000000001';
        const accountState = AccountState(
          accounts: [
            AccountInfo(
              uuid: 'linked-ledger',
              name: 'Imported Ledger',
              order: 0,
              isHardware: true,
              hardwareSignerKind: HardwareSignerKind.ledger,
              zip32AccountIndex: 7,
              birthdayHeight: 3000000,
              ledgerWalletFingerprint: fingerprint,
            ),
          ],
        );
        final notifier = _FakeAccountNotifier(accountState);
        var exports = 0;
        var birthdayVisits = 0;
        await tester.pumpWidget(
          _ledgerHarness(
            ble: ble,
            accountState: accountState,
            accountNotifier: notifier,
            connectionAccountUuid: 'linked-ledger',
            ufvkLoader: (uuid) async {
              expect(uuid, 'linked-ledger');
              return 'uview1stored';
            },
            identityConnector: (_) async => LedgerWalletIdentity(
              fingerprint: mismatch == 'wallet'
                  ? 'different-wallet'
                  : fingerprint,
            ),
            connector: (index) async {
              exports++;
              expect(index, 7);
              return LedgerDeviceAccount(
                ufvk: mismatch == 'ufvk' ? 'uview1other' : 'uview1stored',
                seedFingerprint: List.filled(32, 7),
                accountIndex: index,
                appVersion: '3.9.3',
              );
            },
            onBirthday: (_) => birthdayVisits++,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Connect the Ledger for this account.'),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey('mobile_ledger_advanced_options_disclosure'),
          ),
          findsNothing,
        );
        expect(
          tester
              .getBottomRight(
                find.byKey(const ValueKey('mobile_ledger_import_button')),
              )
              .dy,
          lessThanOrEqualTo(700),
        );
        await _selectLedger(tester, ble);
        await tester.tap(
          find.byKey(const ValueKey('mobile_ledger_import_button')),
        );
        await tester.pumpAndSettle();
        expect(birthdayVisits, 0);
        expect(exports, mismatch == 'wallet' ? 0 : 1);
        if (mismatch == 'none') {
          expect(find.text('connection-return'), findsOneWidget);
          expect(notifier.connectedUuid, 'linked-ledger');
          expect(notifier.connectedDeviceId, 'ledger');
          expect(notifier.preference, LedgerConnectionPreference.bluetooth);
        } else {
          expect(
            find.byKey(const ValueKey('mobile_ledger_connect_error')),
            findsOneWidget,
          );
          expect(notifier.connectedUuid, isNull);
          expect(notifier.preference, isNull);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final cancel in [false, true]) {
    testWidgets(
      'first-signature connection requires an explicit retry, cancel=$cancel',
      (tester) async {
        final ble = _FakeBleService();
        const accountState = AccountState(
          accounts: [
            AccountInfo(
              uuid: 'linked-ledger',
              name: 'Imported Ledger',
              order: 0,
              isHardware: true,
              hardwareSignerKind: HardwareSignerKind.ledger,
              zip32AccountIndex: 7,
              ledgerWalletFingerprint:
                  '0000000000000000000000000000000000000000000000000000000000000001',
            ),
          ],
        );
        var signatures = 0;
        var reconnects = 0;
        await tester.pumpWidget(
          _ledgerHarness(
            ble: ble,
            accountState: accountState,
            startAtSigning: true,
            onSign: () => signatures++,
            reconnect: (_) async => reconnects++,
            ufvkLoader: (_) async => 'uview1stored',
            connector: (index) async => LedgerDeviceAccount(
              ufvk: 'uview1stored',
              seedFingerprint: List.filled(32, 7),
              accountIndex: index,
              appVersion: '3.9.3',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Reconnect'));
        await tester.tap(find.text('Reconnect'));
        await tester.pumpAndSettle();
        expect(
          find.text('Connect the Ledger for this account.'),
          findsOneWidget,
        );
        if (cancel) {
          Navigator.of(
            tester.element(find.byType(MobileLedgerConnectScreen)),
          ).pop();
        } else {
          await _selectLedger(tester, ble);
          await tester.tap(
            find.byKey(const ValueKey('mobile_ledger_import_button')),
          );
        }
        await tester.pumpAndSettle();
        expect(signatures, 0);
        expect(reconnects, 0);
        if (cancel) {
          expect(
            find.text('Connect your Ledger before retrying.'),
            findsOneWidget,
          );
          expect(find.text('Ready when you are'), findsNothing);
        } else {
          expect(find.text('Ready when you are'), findsOneWidget);
          await tester.tap(find.text('Try again'));
          expect(signatures, 1);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'prioritizes device selection and keeps Continue visible on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(393, 700);
      final ble = _FakeBleService();
      await tester.pumpWidget(
        _ledgerHarness(ble: ble, connector: (_) => throw StateError('unused')),
      );
      await tester.pumpAndSettle();

      final select = find.byKey(
        const ValueKey('mobile_ledger_select_device_button'),
      );
      final prompt = find.byKey(
        const ValueKey('ledger_connection_preparation'),
      );
      final submit = find.byKey(const ValueKey('mobile_ledger_import_button'));
      expect(
        tester.getTopLeft(select).dy,
        lessThan(tester.getTopLeft(prompt).dy),
      );
      expect(tester.getBottomRight(submit).dy, lessThanOrEqualTo(700));
      final submitSurface = find.descendant(
        of: submit,
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(submitSurface).width, 393 - AppSpacing.sm * 2);
      expect(tester.widget<AppButton>(submit).onPressed, isNull);
      expect(
        find.byKey(const ValueKey('mobile_ledger_account_index_field')),
        findsNothing,
      );
      expect(find.textContaining('watch-only'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps a long nearby-device list scrollable on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 700);
    final ble = _FakeBleService();
    await tester.pumpWidget(
      _ledgerHarness(ble: ble, connector: (_) => throw StateError('unused')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('mobile_ledger_select_device_button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_ledger_select_device_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    ble.emit(
      LedgerDevicesDiscovered([
        for (var index = 0; index < 8; index++)
          LedgerBleDevice(
            id: 'device-$index',
            name: 'Personal Ledger device $index',
            model: 'Nano X',
          ),
      ]),
    );
    await tester.pump();

    final list = find.byKey(const ValueKey('mobile_ledger_device_list'));
    expect(tester.getSize(list).height, lessThanOrEqualTo(280));
    expect(tester.takeException(), isNull);
    await tester.drag(list, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile_ledger_device_device-7')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows connection errors without hiding the discovered device', (
    tester,
  ) async {
    final ble = _FakeBleService(
      connectError: const LedgerMobileException(
        LedgerMobileFailure.disconnected,
        'Your Ledger disconnected. Keep it nearby, then try again.',
      ),
    );
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
        LedgerBleDevice(id: 'ledger', name: 'Personal Ledger', model: 'Nano X'),
      ]),
    );
    await tester.pump();
    await tester.tap(find.text('Personal Ledger'));
    await tester.pumpAndSettle();

    expect(find.text('Personal Ledger'), findsOneWidget);
    expect(
      find.text('Your Ledger disconnected. Keep it nearby, then try again.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows pending-request recovery instead of scanning and can retry',
    (tester) async {
      const message =
          'Finish or reject the pending request on your Ledger, then try again.';
      final ble = _FakeBleService()
        ..disconnectError = const LedgerMobileException(
          LedgerMobileFailure.unavailable,
          message,
        );
      await tester.pumpWidget(
        _ledgerHarness(ble: ble, connector: (_) => throw StateError('unused')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('mobile_ledger_select_device_button')),
      );
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile_ledger_scanning')),
        findsNothing,
      );
      expect(ble.permissionCalls, 0);

      ble.disconnectError = null;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      ble.emit(
        const LedgerDevicesDiscovered([
          LedgerBleDevice(id: 'ledger', name: 'Ready Ledger', model: 'Nano X'),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready Ledger'), findsOneWidget);
      expect(find.text(message), findsNothing);
      expect(ble.disconnectCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving UFVK approval cancels once and ignores a late account', (
    tester,
  ) async {
    final ble = _FakeBleService();
    final approval = Completer<LedgerDeviceAccount>();
    var cancels = 0;
    var birthdays = 0;
    var exports = 0;
    await tester.pumpWidget(
      _ledgerHarness(
        ble: ble,
        connector: (_) {
          exports++;
          return approval.future;
        },
        canceller: () async {
          cancels++;
        },
        onBirthday: (_) => birthdays++,
      ),
    );
    await tester.pumpAndSettle();
    await _selectLedger(tester, ble);
    await tester.tap(find.byKey(const ValueKey('mobile_ledger_import_button')));
    await tester.pump();
    expect(exports, 1);
    expect(find.text('Waiting for Ledger'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(cancels, 1);
    approval.complete(
      const LedgerDeviceAccount(
        ufvk: 'uview-late',
        seedFingerprint: [1, 2, 3],
        accountIndex: 0,
        appVersion: '3.9.3',
      ),
    );
    await tester.pumpAndSettle();
    expect(birthdays, 0);
    expect(cancels, 1);
    expect(tester.takeException(), isNull);
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
        expect(
          find.byKey(const ValueKey('mobile_welcome_ledger')),
          findsOneWidget,
        );
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
        '/onboarding/ledger/set-passcode',
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

  testWidgets('discovers, connects, and exports the selected Ledger', (
    tester,
  ) async {
    final ble = _FakeBleService(failCleanupStopsAfter: 2);
    final accountApproval = Completer<LedgerDeviceAccount>();
    var connectorCalls = 0;
    int? requestedIndex;
    LedgerBirthdayArgs? birthdayArgs;

    await tester.pumpWidget(
      _ledgerHarness(
        ble: ble,
        connector: (index) async {
          connectorCalls++;
          requestedIndex = index;
          return accountApproval.future;
        },
        onBirthday: (args) => birthdayArgs = args,
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
    await tester.tap(find.text('Rowan Ledger'));
    await tester.pump();
    expect(find.text('Connecting to Rowan Ledger'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));

    expect(ble.connectedIds, ['nano-x']);
    expect(find.text('Rowan Ledger'), findsOneWidget);
    expect(find.text('Nano X'), findsOneWidget);

    final advanced = find.byKey(
      const ValueKey('mobile_ledger_advanced_options_disclosure'),
    );
    await tester.ensureVisible(advanced);
    await tester.tap(advanced);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile_ledger_account_index_field')),
      '12',
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
        ufvk: 'uview-12',
        seedFingerprint: [1, 2, 3],
        accountIndex: 12,
        appVersion: '3.9.3',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('birthday-route-bluetooth-Nano X'), findsOneWidget);
    expect(connectorCalls, 1);
    expect(requestedIndex, 12);
    expect(birthdayArgs?.sourceAccountUuid, isNull);
    expect(
      birthdayArgs?.account.walletFingerprint,
      '0000000000000000000000000000000000000000000000000000000000000001',
    );
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
    await tester.tap(find.text('Rowan Ledger'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ble.connectedIds, ['stax']);

    await openPickerAndDiscover();
    expect(
      find.byKey(const ValueKey('mobile_ledger_device_stax')),
      findsOneWidget,
    );
    expect(ble.disconnectCalls, 2);
  });

  testWidgets(
    'shows same-wallet accounts, suggests the first gap, and blocks duplicates',
    (tester) async {
      const fingerprint =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      var identityCalls = 0;
      var connectorCalls = 0;
      final ble = _FakeBleService();
      await tester.pumpWidget(
        _ledgerHarness(
          ble: ble,
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
          identityConnector: (_) async {
            identityCalls++;
            return const LedgerWalletIdentity(fingerprint: fingerprint);
          },
          connector: (_) async {
            connectorCalls++;
            throw StateError('duplicate must stop before device requests');
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Primary Ledger account'), findsOneWidget);
      expect(find.text('Savings'), findsOneWidget);
      expect(find.text('Different Ledger'), findsNothing);
      expect(find.text('Next available index: 1'), findsOneWidget);

      await _selectLedger(tester, ble);
      final disclosure = find.byKey(
        const ValueKey('mobile_ledger_advanced_options_disclosure'),
      );
      await tester.ensureVisible(disclosure);
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      final field = tester.widget<AppTextField>(
        find.byKey(const ValueKey('mobile_ledger_account_index_field')),
      );
      expect(field.controller!.text, '1');
      final importButton = find.byKey(
        const ValueKey('mobile_ledger_import_button'),
      );
      await tester.enterText(
        find.byKey(const ValueKey('mobile_ledger_account_index_field')),
        '2147483648',
      );
      await tester.ensureVisible(importButton);
      await tester.tap(importButton);
      await tester.pumpAndSettle();
      expect(
        find.text('Account index must be between 0 and 2147483647.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('mobile_ledger_account_index_field')),
        '2',
      );
      await tester.ensureVisible(importButton);
      await tester.tap(importButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Index 2 is already used by this Ledger wallet.'),
        findsOneWidget,
      );
      expect(identityCalls, 0);

      final indexInput = find.byKey(
        const ValueKey('mobile_ledger_account_index_field'),
      );
      final indexMessage = find.byKey(
        const ValueKey('mobile_ledger_account_index_message'),
      );
      expect(tester.widget<AppTextField>(indexInput).messageText, isNull);
      expect(
        tester.getRect(indexMessage).top,
        greaterThan(tester.getRect(indexInput).bottom),
      );
      expect(
        find.text(
          'Use a different index to restore or add another Ledger account.',
        ),
        findsNothing,
      );

      await tester.enterText(indexInput, '1');
      await tester.pumpAndSettle();
      expect(
        find.text('Index 2 is already used by this Ledger wallet.'),
        findsNothing,
      );
      expect(
        find.text(
          'Use a different index to restore or add another Ledger account.',
        ),
        findsOneWidget,
      );
      expect(connectorCalls, 0);
    },
  );

  testWidgets('stops a wrong Ledger before requesting the target UFVK', (
    tester,
  ) async {
    var connectorCalls = 0;
    final ble = _FakeBleService();
    await tester.pumpWidget(
      _ledgerHarness(
        ble: ble,
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
        identityConnector: (_) async => const LedgerWalletIdentity(
          fingerprint:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
        connector: (_) async {
          connectorCalls++;
          throw StateError('must not request UFVK');
        },
      ),
    );
    await tester.pumpAndSettle();
    await _selectLedger(tester, ble);
    final importButton = find.byKey(
      const ValueKey('mobile_ledger_import_button'),
    );
    await tester.ensureVisible(importButton);
    await tester.tap(importButton);
    await tester.pumpAndSettle();

    expect(
      find.text('This Ledger does not match the account you started from.'),
      findsOneWidget,
    );
    expect(connectorCalls, 0);
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
  LedgerBluetoothWalletIdentityConnector? identityConnector,
  LedgerOperationCanceller? canceller,
  AccountState accountState = const AccountState(
    accounts: [AccountInfo(uuid: 'software', name: 'Main', order: 0)],
  ),
  String? sourceAccountUuid,
  String? connectionAccountUuid,
  _FakeAccountNotifier? accountNotifier,
  Future<String> Function(String)? ufvkLoader,
  bool startAtSigning = false,
  VoidCallback? onSign,
  Future<void> Function(String)? reconnect,
  ValueChanged<LedgerBirthdayArgs>? onBirthday,
}) {
  final router = GoRouter(
    initialLocation: startAtSigning
        ? '/signing'
        : connectionAccountUuid == null
        ? '/onboarding/ledger'
        : '/connection/connect',
    routes: [
      GoRoute(
        path: '/signing',
        builder: (_, _) => Scaffold(
          body: LedgerSigningModal(
            pageLayout: true,
            accountUuid: 'linked-ledger',
            phase: LedgerSigningModalPhase.failed,
            failure: const LedgerSigningFailurePresentation(
              title: 'Connection required',
              statusLabel: 'Disconnected',
              message: 'Connect your Ledger with Bluetooth, then try again.',
              requiresReconnect: true,
            ),
            onCancel: () {},
            onFailureAction: onSign,
          ),
        ),
      ),
      GoRoute(
        path: '/connection',
        builder: (_, _) => const Text('connection-return'),
        routes: [
          GoRoute(
            path: 'connect',
            builder: (_, _) => MobileLedgerConnectScreen(
              connectionAccountUuid: connectionAccountUuid,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/onboarding/ledger',
        builder: (_, _) =>
            MobileLedgerConnectScreen(sourceAccountUuid: sourceAccountUuid),
      ),
      GoRoute(
        path: '/onboarding/ledger/birthday',
        builder: (_, state) {
          final args = state.extra! as LedgerBirthdayArgs;
          onBirthday?.call(args);
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
        _bootstrap(accounts: accountState.accounts),
      ),
      accountProvider.overrideWith(
        () => accountNotifier ?? _FakeAccountNotifier(accountState),
      ),
      if (ufvkLoader != null)
        ledgerAccountUfvkLoaderProvider.overrideWithValue(ufvkLoader),
      if (startAtSigning)
        ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.iOS),
      if (reconnect != null)
        ledgerReconnectProvider.overrideWithValue(reconnect),
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
      ledgerBluetoothWalletIdentityConnectorProvider.overrideWithValue(
        identityConnector ??
            (_) async => const LedgerWalletIdentity(
              fingerprint:
                  '0000000000000000000000000000000000000000000000000000000000000001',
            ),
      ),
      ledgerOperationCancellerProvider.overrideWithValue(
        canceller ?? () async {},
      ),
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

Future<void> _selectLedger(WidgetTester tester, _FakeBleService ble) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey('mobile_ledger_select_device_button')),
  );
  await tester.tap(
    find.byKey(const ValueKey('mobile_ledger_select_device_button')),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  ble.emit(
    const LedgerDevicesDiscovered([
      LedgerBleDevice(id: 'ledger', name: 'Rowan Ledger', model: 'Flex'),
    ]),
  );
  await tester.pump();
  await tester.tap(find.text('Rowan Ledger'));
  await tester.pump(const Duration(milliseconds: 300));
}

AppBootstrapState _bootstrap({
  required List<AccountInfo> accounts,
  bool passwordConfigured = true,
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
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(chainTipHeight: 4000000);
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.initialState);

  final AccountState initialState;
  String? connectedUuid;
  String? connectedDeviceId;
  LedgerConnectionPreference? preference;

  @override
  Future<void> recordLedgerConnection({
    required String uuid,
    required LedgerConnectionTransport transport,
    String? deviceId,
    String? deviceName,
    String? deviceModel,
  }) async {
    connectedUuid = uuid;
    connectedDeviceId = deviceId;
  }

  @override
  Future<void> updateLedgerConnectionPreference(
    String uuid,
    LedgerConnectionPreference value,
  ) async {
    preference = value;
  }

  @override
  Future<AccountState> build() async => initialState;
}

class _FakeReadinessController extends LedgerAppReadinessController {
  @override
  LedgerAppReadinessState build() => const LedgerAppReadinessState.idle();
}

class _FakeBleService implements LedgerMobileBleService {
  _FakeBleService({
    List<bool> permissionResults = const [true],
    this.failCleanupStopsAfter,
    this.connectError,
  }) : _permissionResults = permissionResults;

  final List<bool> _permissionResults;
  final int? failCleanupStopsAfter;
  final Object? connectError;
  Object? disconnectError;
  final _updates = StreamController<LedgerDiscoveryUpdate>.broadcast(
    sync: true,
  );
  final List<String> connectedIds = [];
  final List<String> calls = [];
  int permissionCalls = 0;
  int stopCalls = 0;
  int disconnectCalls = 0;

  @override
  String? connectedDeviceId;

  void emit(LedgerDiscoveryUpdate update) => _updates.add(update);

  @override
  Future<void> connect(LedgerBleDevice device) async {
    calls.add('connect');
    if (connectError case final error?) throw error;
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
    if (disconnectError case final error?) throw error;
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
  Future<void> cancelSigning() async {}

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
    final threshold = failCleanupStopsAfter;
    if (threshold != null && stopCalls > threshold) {
      throw const LedgerMobileException(
        LedgerMobileFailure.unavailable,
        'Cleanup failed.',
      );
    }
  }
}
