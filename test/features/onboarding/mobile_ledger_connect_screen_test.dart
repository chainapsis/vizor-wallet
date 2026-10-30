@Tags(['mobile'])
library;

import 'dart:async';
import '../../support/ledger_discovery_channel.dart';
import '../../figma_compare/figma_compare_font_loader.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_failure_guidance.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress_scope.dart';

import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile/mobile_ledger_sheet_content.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_text_field.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_procedure.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_ledger_connect_screen.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile_ledger_signing_surface.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_ledger_device_sheet.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_hardware_selection_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_setup_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart' as rust_ledger;

const _captureDirectory = String.fromEnvironment('LEDGER_CAPTURE_DIR');
const _captureKey = ValueKey('mobile_ledger_connect_capture');

void main() {
  setUpAll(loadFigmaCompareFonts);
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
  });

  group('mobile hardware selection Ledger visibility', () {
    testWidgets('shows Ledger for iOS and Android mainnet software wallets', (
      tester,
    ) async {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        await tester.pumpWidget(
          _hardwareHarness(
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
        _hardwareHarness(
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
          _hardwareHarness(
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
        _hardwareHarness(
          bootstrap: _bootstrap(accounts: const [account]),
          platform: TargetPlatform.windows,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect Ledger'), findsNothing);

      await tester.pumpWidget(
        _hardwareHarness(
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
            builder: (_, child) => AppTheme(
              data: AppThemeData.light,
              child: MobileOnboardingProgressFrame(child: child!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connect Ledger'), findsNWidgets(2));
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

  testWidgets(
    'validates index before discovery and exports immediately after selection',
    (tester) async {
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
      await _capture(tester, 'connect-ready');
      final submit = find.byKey(const ValueKey('mobile_ledger_import_button'));
      final button = tester.widget<AppButton>(submit);
      expect(button.onPressed, isNotNull);
      expect((button.trailing! as AppIcon).name, AppIcons.chevronForward);
      expect(ble.permissionCalls, 0);
      await tester.tap(
        find.byKey(const ValueKey('mobile_ledger_advanced_options_disclosure')),
      );
      await tester.pumpAndSettle();
      await _capture(tester, 'connect-advanced');
      final field = find.byKey(
        const ValueKey('mobile_ledger_account_index_field'),
      );
      final fieldBeforeError = tester.getRect(field);
      final actionBeforeError = tester.getRect(submit);
      for (final invalid in ['101', '102', '', '999999999999999999999999']) {
        await tester.enterText(
          find.byKey(const ValueKey('mobile_ledger_account_index_field')),
          invalid,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Account index must be between 0 and 100.'),
          findsOneWidget,
        );
        expect(ble.permissionCalls, 0);
        expect(connectorCalls, 0);
        expect(tester.getRect(field), fieldBeforeError);
        expect(tester.getRect(submit), actionBeforeError);
        expect(
          tester
              .widget<AppTextField>(
                find.byKey(const ValueKey('mobile_ledger_account_index_field')),
              )
              .tone,
          AppTextFieldTone.destructive,
        );
        if (invalid == '101') {
          await _capture(tester, 'connect-advanced-invalid');
        }
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(ble.permissionCalls, 0);
        expect(tester.getRect(field), fieldBeforeError);
      }
      for (final valid in ['0', '100']) {
        await tester.enterText(
          find.byKey(const ValueKey('mobile_ledger_account_index_field')),
          valid,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Account index must be between 0 and 100.'),
          findsNothing,
        );
        expect(ble.permissionCalls, 0);
      }
      await _capture(tester, 'connect-advanced-corrected');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _selectLedger(tester, ble);
      await _capture(tester, 'connect-approval');
      expect(ble.connectedIds, ['nano-x']);
      expect(connectorCalls, 1);
      expect(requestedIndex, 100);
      expect(find.text('Add Ledger account'), findsOneWidget);
      expect(find.text('Add account'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      expect(
        find.text('Approve sharing the viewing key for Account #101.'),
        findsOneWidget,
      );
      expect(
        ble.stopCalls,
        2,
        reason: 'Picker stays mounted during the viewing-key request.',
      );
      accountApproval.complete(
        const LedgerDeviceAccount(
          ufvk: 'uview-100',
          seedFingerprint: [1, 2, 3],
          accountIndex: 100,
          appVersion: '3.9.4',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('birthday-route-bluetooth-Nano X'), findsOneWidget);
      expect(connectorCalls, 1);
      expect(ble.stopCalls, greaterThanOrEqualTo(3));
    },
  );

  for (final failure in ['locked', 'rejected']) {
    for (final dropped in [false, true]) {
      testWidgets(
        'account retry reconnects after $failure (dropped: $dropped)',
        (tester) async {
          final native = LedgerDiscoveryChannel();
          native.currentAppError = PlatformException(code: failure);
          var reads = 0;
          await tester.pumpWidget(
            _ledgerHarness(
              ble: native.service,
              connector: (index) async {
                reads++;
                await native.service.currentApp();
                return LedgerDeviceAccount(
                  ufvk: 'test',
                  seedFingerprint: const [],
                  accountIndex: index,
                  appVersion: '3.9.4',
                );
              },
            ),
          );
          await tester.pump();
          await tester.tap(
            find.byKey(const ValueKey('mobile_ledger_import_button')),
          );
          await pumpLedgerDiscovery(tester);
          await native.devices();
          await pumpLedgerDiscovery(tester);
          await tester.tap(find.text('Ledger Stax · A37E'));
          await pumpLedgerDiscovery(tester);
          expect(reads, 1);
          expect(native.calls.where((c) => c == 'connect'), hasLength(1));
          expect(find.text('Try again'), findsOneWidget);
          if (dropped) native.dropConnection();
          expect(native.service.connectedDeviceId, 'stax');
          native.currentAppError = null;
          final cleanup = Completer<void>();
          native.disconnecting = cleanup.future;
          await tester.tap(find.text('Try again'));
          await pumpLedgerDiscovery(tester);
          // No account request may start until native cleanup finishes.
          expect(reads, 1);
          expect(native.calls.where((c) => c == 'connect'), hasLength(1));
          final procedure = tester.widget<LedgerProcedure>(
            find.byType(LedgerProcedure),
          );
          expect(procedure.currentStep, 0);
          expect(procedure.steps.first.busy, isTrue);
          cleanup.complete();
          await pumpLedgerDiscovery(tester);
          expect(reads, 2);
          expect(native.calls.where((c) => c == 'connect'), hasLength(2));
          expect(
            find.text('birthday-route-bluetooth-Ledger Stax'),
            findsOneWidget,
          );
          // Retry the selected device without reopening discovery.
          expect(
            native.calls.where((c) => c == 'startDiscovery'),
            hasLength(1),
          );
          await tester.pumpWidget(const SizedBox());
          await pumpLedgerDiscovery(tester);
          await tester.runAsync(native.dispose);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.iOS,
          TargetPlatform.android,
        }),
      );
    }
  }

  for (final action in ['cancel', 'cleanup failure']) {
    testWidgets(
      'account retry stops after $action during reconnection',
      (tester) async {
        final native = LedgerDiscoveryChannel();
        native.currentAppError = PlatformException(code: 'locked');
        var reads = 0;
        await tester.pumpWidget(
          _ledgerHarness(
            ble: native.service,
            cancel: native.service.cancelSigning,
            connector: (index) async {
              reads++;
              await native.service.currentApp();
              return LedgerDeviceAccount(
                ufvk: 'test',
                seedFingerprint: const [],
                accountIndex: index,
                appVersion: '3.9.4',
              );
            },
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('mobile_ledger_import_button')),
        );
        await pumpLedgerDiscovery(tester);
        await native.devices();
        await pumpLedgerDiscovery(tester);
        await tester.tap(find.text('Ledger Stax · A37E'));
        await pumpLedgerDiscovery(tester);
        expect(reads, 1);
        native.currentAppError = null;
        final cleanup = Completer<void>();
        if (action == 'cancel') {
          native.disconnecting = cleanup.future;
        } else {
          native.disconnectError = PlatformException(code: 'busy');
        }
        await tester.tap(find.text('Try again'));
        await pumpLedgerDiscovery(tester);
        expect(reads, 1);
        expect(native.calls.where((c) => c == 'connect'), hasLength(1));
        if (action == 'cancel') {
          await tester.tap(_closeButton);
          await pumpLedgerDiscovery(tester);
          cleanup.complete();
          await pumpLedgerDiscovery(tester);
          expect(reads, 1);
          expect(native.calls.where((c) => c == 'connect'), hasLength(1));
          expect(find.byType(LedgerProcedure), findsNothing);
        } else {
          expect(find.text('Try again'), findsOneWidget);
          native.disconnectError = null;
          await tester.tap(find.text('Try again'));
          await pumpLedgerDiscovery(tester);
          expect(reads, 2);
          expect(native.calls.where((c) => c == 'connect'), hasLength(2));
          expect(
            find.text('birthday-route-bluetooth-Ledger Stax'),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox());
        await pumpLedgerDiscovery(tester);
        await tester.runAsync(native.dispose);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }

  testWidgets(
    'declined viewing key stays in the sheet and retries without discovery',
    (tester) async {
      final ble = _FakeBleService();
      var exports = 0;
      await tester.pumpWidget(
        _ledgerHarness(
          ble: ble,
          connector: (_) async {
            exports++;
            throw const LedgerMobileException(
              LedgerMobileFailure.rejected,
              'declined',
            );
          },
        ),
      );
      await _selectLedger(tester, ble);
      await _capture(tester, 'connect-declined');
      expect(find.text('Request declined'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is AppIcon && w.name == AppIcons.loader,
        ),
        findsNothing,
      );
      expect(find.text('Add account'), findsOneWidget);
      expect(exports, 1);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(exports, 2);
      expect(ble.connectedIds, ['nano-x', 'nano-x']);
      expect(ble.permissionCalls, 1);
    },
  );

  testWidgets(
    'closing an account request ignores its late result and can start a fresh session',
    (tester) async {
      final ble = _FakeBleService();
      final pending = Completer<LedgerDeviceAccount>();
      var exports = 0;
      var cancellations = 0;
      await tester.pumpWidget(
        _ledgerHarness(
          ble: ble,
          connector: (_) {
            exports++;
            return exports == 1
                ? pending.future
                : Completer<LedgerDeviceAccount>().future;
          },
          cancel: () async {
            cancellations++;
          },
        ),
      );
      await _selectLedger(tester, ble);
      await tester.tap(_closeButton);
      await tester.pump();
      expect(cancellations, 1);
      expect(find.text('Add Ledger account'), findsNothing);
      await _selectLedger(tester, ble);
      expect(exports, 2);
      pending.complete(
        const LedgerDeviceAccount(
          ufvk: 'late',
          seedFingerprint: [1],
          accountIndex: 0,
          appVersion: '3.9.4',
        ),
      );
      await tester.pump();
      expect(find.text('birthday-route-bluetooth-Nano X'), findsNothing);
      expect(find.text('Add Ledger account'), findsOneWidget);
      expect(
        find.text('Approve sharing the viewing key for Account #1.'),
        findsOneWidget,
      );
    },
  );

  for (final action in ['button', 'system']) {
    testWidgets(
      '$action Back drains the request and selects another Ledger in the same sheet',
      (tester) async {
        final ble = _FakeBleService();
        final first = Completer<LedgerDeviceAccount>();
        final second = Completer<LedgerDeviceAccount>();
        final cancellation = Completer<void>();
        final disconnect = Completer<void>();
        final requestedIndices = <int>[];
        var cancellations = 0;
        await tester.pumpWidget(
          _ledgerHarness(
            ble: ble,
            connector: (index) {
              requestedIndices.add(index);
              return requestedIndices.length == 1
                  ? first.future
                  : second.future;
            },
            cancel: () {
              cancellations++;
              return cancellation.future;
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey('mobile_ledger_advanced_options_disclosure'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('mobile_ledger_account_index_field')),
          '7',
        );
        await _selectLedger(tester, ble);
        final surface = tester.element(find.byType(MobileLedgerSigningSurface));
        final back = find.byKey(const ValueKey('mobile_modal_back_button'));
        expect(back, findsOneWidget);
        final backRect = tester.getRect(back);
        final sheet = tester.getRect(find.byType(MobileLedgerSheetContent));
        expect(backRect.size, const Size(44, 44));
        expect(backRect.bottom, closeTo(sheet.top - 8, .1));
        ble.pendingDisconnect = disconnect.future;
        if (action == 'button') {
          await tester.tap(back);
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pump();
        expect(cancellations, 1);
        expect(tester.widget<AppButton>(back).onPressed, isNull);
        expect(ble.permissionCalls, 1);
        await tester.binding.handlePopRoute();
        await tester.tapAt(const Offset(10, 10));
        await tester.pump();
        expect(cancellations, 1);
        if (action == 'button') {
          await _capture(tester, 'connect-changing-device');
        }
        cancellation.complete();
        await tester.pump();
        expect(ble.disconnectCalls, 2);
        expect(
          ble.permissionCalls,
          1,
          reason: 'Discovery waits for native cleanup.',
        );
        // An approval that arrives during cleanup must not open the birthday page.
        first.complete(
          const LedgerDeviceAccount(
            ufvk: 'late',
            seedFingerprint: [1],
            accountIndex: 7,
            appVersion: '3.9.4',
          ),
        );
        await tester.pump();
        expect(find.text('birthday-route-bluetooth-Nano X'), findsNothing);
        expect(
          tester.element(find.byType(MobileLedgerSigningSurface)),
          same(surface),
        );
        ble.pendingDisconnect = null;
        disconnect.complete();
        await tester.pump();
        await tester.pump();
        expect(back, findsNothing);
        expect(ble.permissionCalls, 2);
        expect(
          find.byKey(const ValueKey('mobile_ledger_device_sheet')),
          findsOneWidget,
        );
        expect(
          tester.element(find.byType(MobileLedgerSigningSurface)),
          same(surface),
        );
        ble.emit(
          const LedgerDevicesDiscovered([
            LedgerBleDevice(id: 'stax', name: 'Other Ledger', model: 'Stax'),
          ]),
        );
        await tester.pump();
        if (action == 'button') {
          await _capture(tester, 'connect-reselect-device');
        }
        await tester.tap(find.text('Ledger Stax · Other Ledger'));
        await tester.pump();
        expect(requestedIndices, [7, 7]);
        expect(ble.connectedIds, ['nano-x', 'stax']);
        expect(find.text('Ledger Stax · Other Ledger'), findsOneWidget);
        second.complete(
          const LedgerDeviceAccount(
            ufvk: 'other',
            seedFingerprint: [2],
            accountIndex: 7,
            appVersion: '3.9.4',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('birthday-route-bluetooth-Stax'), findsOneWidget);
      },
    );
  }

  for (final failure in [
    'cancellation',
    'disconnect',
    'pending device request',
  ]) {
    testWidgets('Back retries failed $failure before returning to selection', (
      tester,
    ) async {
      final ble = _FakeBleService();
      var cancellations = 0;
      var exports = 0;
      await tester.pumpWidget(
        _ledgerHarness(
          ble: ble,
          connector: (_) {
            exports++;
            return Completer<LedgerDeviceAccount>().future;
          },
          cancel: () async {
            if (++cancellations == 1 && failure == 'cancellation') {
              throw StateError('cleanup');
            }
          },
        ),
      );
      await _selectLedger(tester, ble);
      if (failure != 'cancellation') ble.failDisconnectOnCall = 2;
      if (failure == 'pending device request') {
        ble.disconnectFailure = const LedgerMobileException(
          LedgerMobileFailure.busy,
          'Finish the pending request.',
        );
      }
      await tester.tap(find.byKey(const ValueKey('mobile_modal_back_button')));
      await tester.pump();
      expect(find.text('Could not cancel Ledger request'), findsOneWidget);
      if (failure == 'pending device request') {
        expect(
          find.text(
            'Another Ledger request is still active. Complete or reject it on your Ledger, then try again.',
          ),
          findsOneWidget,
        );
        await _capture(tester, 'connect-back-pending-request');
      }
      expect(ble.permissionCalls, 1);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      expect(cancellations, 2);
      expect(exports, 1);
      expect(
        find.byKey(const ValueKey('mobile_ledger_device_sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile_modal_back_button')),
        findsNothing,
      );
      expect(ble.permissionCalls, 2);
      // X still leaves the entire connection flow from the picker.
      await tester.tap(_closeButton);
      await tester.pump();
      expect(find.byType(MobileLedgerSigningSurface), findsNothing);
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('mobile_ledger_import_button')),
            )
            .onPressed,
        isNotNull,
      );
    });
  }

  testWidgets(
    'Back and current guidance stay reachable at 320px with 2x text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
      final ble = _FakeBleService();
      await tester.pumpWidget(
        _ledgerHarness(
          ble: ble,
          connector: (_) => Completer<LedgerDeviceAccount>().future,
          textScale: 2,
        ),
      );
      await _selectLedger(tester, ble);
      final back = find.byKey(const ValueKey('mobile_modal_back_button'));
      await _capture(tester, 'connect-back-320-2x');
      expect(back.hitTestable(), findsOneWidget);
      expect(_closeButton.hitTestable(), findsOneWidget);
      final viewport = tester.getRect(
        find.descendant(
          of: find.byType(MobileLedgerSheetContent),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Add account')).dy,
        greaterThanOrEqualTo(viewport.top - 1),
      );
      expect(
        tester.getTopLeft(find.text('Add account')).dy,
        lessThan(viewport.bottom),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(back);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('mobile_ledger_device_sheet')),
        findsOneWidget,
      );
      expect(back, findsNothing);
    },
  );

  testWidgets(
    'failed cancellation retries cleanup instead of exporting again',
    (tester) async {
      final ble = _FakeBleService();
      var exports = 0;
      var cancellations = 0;
      await tester.pumpWidget(
        _ledgerHarness(
          ble: ble,
          connector: (_) {
            exports++;
            return Completer<LedgerDeviceAccount>().future;
          },
          cancel: () async {
            if (++cancellations == 1) throw StateError('cleanup');
          },
        ),
      );
      await _selectLedger(tester, ble);
      await tester.tap(_closeButton);
      await tester.pump();
      expect(find.text('Could not cancel Ledger request'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(cancellations, 2);
      expect(exports, 1);
      expect(find.text('Add Ledger account'), findsNothing);
    },
  );

  testWidgets(
    'collapsed options keep the index and reopen an invalid field before discovery',
    (tester) async {
      final ble = _FakeBleService();
      await tester.pumpWidget(
        _ledgerHarness(
          ble: ble,
          connector: (_) => Completer<LedgerDeviceAccount>().future,
        ),
      );
      await tester.pumpAndSettle();
      final disclosure = find.byKey(
        const ValueKey('mobile_ledger_advanced_options_disclosure'),
      );
      final field = find.byKey(
        const ValueKey('mobile_ledger_account_index_field'),
      );
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      await tester.enterText(field, '7');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(field).bottom,
        lessThanOrEqualTo(
          tester
              .getRect(
                find.byKey(const ValueKey('mobile_ledger_import_button')),
              )
              .top,
        ),
      );
      await tester.enterText(field, '101');
      await tester.pumpAndSettle();
      final error = find.text('Account index must be between 0 and 100.');
      expect(error, findsOneWidget);
      expect(error.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(error).bottom,
        lessThanOrEqualTo(
          tester
              .getRect(
                find.byKey(const ValueKey('mobile_ledger_import_button')),
              )
              .top,
        ),
      );
      expect(
        tester.getRect(field).bottom,
        lessThanOrEqualTo(
          tester
              .getRect(
                find.byKey(const ValueKey('mobile_ledger_import_button')),
              )
              .top,
        ),
      );
      await _capture(tester, 'connect-advanced-invalid-keyboard');
      await tester.enterText(field, '7');
      await tester.pumpAndSettle();
      await tester.ensureVisible(disclosure);
      await tester.tap(disclosure);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      expect(tester.widget<AppTextField>(field).controller!.text, '7');
      await tester.enterText(field, '101');
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('mobile_ledger_import_button')),
      );
      await tester.pumpAndSettle();
      expect(field, findsOneWidget);
      expect(
        find.text('Account index must be between 0 and 100.'),
        findsOneWidget,
      );
      expect(ble.permissionCalls, 0);
      await tester.enterText(field, '7');
      await tester.pump();
      expect(
        find.text('Account index must be between 0 and 100.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'advanced account index and primary action remain reachable at 320px and 2x text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      final ble = _FakeBleService();
      await tester.pumpWidget(
        _ledgerHarness(
          ble: ble,
          connector: (_) => Completer<LedgerDeviceAccount>().future,
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      final disclosure = find.byKey(
        const ValueKey('mobile_ledger_advanced_options_disclosure'),
      );
      await tester.ensureVisible(disclosure);
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      final field = find.byKey(
        const ValueKey('mobile_ledger_account_index_field'),
      );
      final action = find.byKey(const ValueKey('mobile_ledger_import_button'));
      expect(
        tester.getRect(field).bottom,
        lessThanOrEqualTo(tester.getRect(action).top),
      );
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'connect-advanced-320-2x');
      await tester.enterText(field, '101');
      await tester.pumpAndSettle();
      final error = find.text('Account index must be between 0 and 100.');
      expect(error, findsOneWidget);
      expect(error.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(error).bottom,
        lessThanOrEqualTo(tester.getRect(action).top),
      );
      expect(
        tester.getRect(field).bottom,
        lessThanOrEqualTo(tester.getRect(action).top),
      );
      await _capture(tester, 'connect-advanced-invalid-320-2x');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(error).bottom,
        lessThanOrEqualTo(tester.getRect(action).top),
      );
      expect(ble.permissionCalls, 0);
    },
  );

  testWidgets(
    'app readiness and viewing-key approval advance inside the same sheet',
    (tester) async {
      final ble = _FakeBleService();
      await tester.pumpWidget(
        _ledgerHarness(
          ble: ble,
          connector: (_) => Completer<LedgerDeviceAccount>().future,
        ),
      );
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MobileLedgerConnectScreen)),
      );
      final readiness = container.read(
        ledgerAppReadinessStateProvider.notifier,
      );
      readiness.update(
        const LedgerAppReadinessState.inProgress(
          LedgerAppReadinessPhase.checkingDevice,
        ),
      );
      await _selectLedger(tester, ble);
      final surface = tester.element(find.byType(MobileLedgerSigningSurface));
      final pending = find.byWidgetPredicate(
        (w) => w is AppIcon && w.name == AppIcons.loader,
      );
      expect(
        find.text('Keep Ledger connected while Vizor checks the app.'),
        findsOneWidget,
      );
      await _capture(tester, 'connect-checking');
      expect(pending, findsOneWidget);
      readiness.update(
        const LedgerAppReadinessState.inProgress(
          LedgerAppReadinessPhase.confirmOpening,
        ),
      );
      await tester.pump();
      expect(
        tester.element(find.byType(MobileLedgerSigningSurface)),
        same(surface),
      );
      expect(find.text('Confirm opening Zcash on Ledger.'), findsOneWidget);
      expect(find.text('Keep Zcash open.'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.text('Confirm opening Zcash on Ledger.'))
            .style
            ?.fontWeight,
        AppTypography.bodyMediumStrong.fontWeight,
      );
      expect(pending, findsOneWidget);
      await _capture(tester, 'connect-opening');
      readiness.update(const LedgerAppReadinessState.ready('3.9.4'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.element(find.byType(MobileLedgerSigningSurface)),
        same(surface),
      );
      expect(
        find.text('Approve sharing the viewing key for Account #0.'),
        findsOneWidget,
      );
      expect(find.text('Continue'), findsNothing);
      expect(pending, findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.text('Approve sharing the viewing key for Account #0.'),
            )
            .style
            ?.fontWeight,
        AppTypography.bodyMediumStrong.fontWeight,
      );
      await _capture(tester, 'connect-approval');
    },
  );

  testWidgets('device rows support keyboard focus and activation', (
    tester,
  ) async {
    final ble = _FakeBleService();
    var selections = 0;
    await tester.pumpWidget(
      AppTheme(
        data: AppThemeData.light,
        child: MaterialApp(
          home: MobileLedgerDeviceSheet(
            service: ble,
            onSelected: (_) => selections++,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    ble.emit(
      const LedgerDevicesDiscovered([
        LedgerBleDevice(id: 'flex', name: '', model: 'Flex'),
      ]),
    );
    await tester.pump();
    final device = find.text('Ledger Flex');
    for (
      var i = 0;
      i < 8 && !Focus.of(tester.element(device)).hasPrimaryFocus;
      i++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(Focus.of(tester.element(device)).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(ble.connectedIds, ['flex']);
    expect(selections, 1);
  });

  testWidgets(
    'access failures retain guidance when the transport handles its own permissions',
    (tester) async {
      final ble = _FakeBleService();
      await tester.pumpWidget(
        _ledgerHarness(
          ble: ble,
          connector: (_) async => throw const LedgerMobileException(
            LedgerMobileFailure.permissionDenied,
            'permission',
          ),
        ),
      );
      await _selectLedger(tester, ble);
      expect(find.text('Could not add Ledger account'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(
        find.text(
          ledgerFailureGuidance(
            const LedgerMobileException(
              LedgerMobileFailure.permissionDenied,
              'permission',
            ),
          )!.message,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('status 0x6a80 does not read as a device rejection', (
    tester,
  ) async {
    final ble = _FakeBleService();
    var connectorCalls = 0;

    await tester.pumpWidget(
      _ledgerHarness(
        ble: ble,
        connector: (_) async {
          connectorCalls++;
          throw StateError(
            'ledger_status_6a80: Ledger rejected the PCZT data or key path',
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_ledger_import_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    ble.emit(
      const LedgerDevicesDiscovered([
        LedgerBleDevice(id: 'nano-x', name: 'Rowan Ledger', model: 'Nano X'),
      ]),
    );
    await tester.pump();
    await _capture(tester, 'connect-picker');
    await tester.tap(find.text('Ledger Nano X · Rowan Ledger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pump();
    expect(connectorCalls, 1);
    expect(find.text(kLedgerViewingKeyRequestRejectedMessage), findsOneWidget);
    expect(find.textContaining('rejected on your Ledger'), findsNothing);
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
    await tester.tap(find.byKey(const ValueKey('mobile_ledger_import_button')));
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
        await tester.tap(_closeButton);
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
        find.byKey(const ValueKey('mobile_ledger_import_button')),
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
      await tester.binding.handlePopRoute();
      await tester.pump();
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
    await tester.tap(find.byKey(const ValueKey('mobile_ledger_import_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(_closeButton);
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
        find.byKey(const ValueKey('mobile_ledger_import_button')),
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

    await tester.tap(_closeButton);
    await tester.pump();
    await openPickerAndDiscover();
    expect(
      find.byKey(const ValueKey('mobile_ledger_device_stax')),
      findsOneWidget,
    );
    expect(ble.disconnectCalls, 2);
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (_captureDirectory.isEmpty) return;
  await tester.pump(const Duration(milliseconds: 300));
  await expectLater(
    find.byKey(_captureKey),
    matchesGoldenFile('$_captureDirectory/$name.png'),
  );
}

final _closeButton = find.bySemanticsLabel('Close');

Future<void> _selectLedger(WidgetTester tester, _FakeBleService ble) async {
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('mobile_ledger_import_button')));
  await tester.pump();
  ble.emit(
    const LedgerDevicesDiscovered([
      LedgerBleDevice(id: 'nano-x', name: 'Rowan Ledger', model: 'Nano X'),
    ]),
  );
  await tester.pump();
  await _capture(tester, 'connect-picker');
  await tester.tap(find.text('Ledger Nano X · Rowan Ledger'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Widget _hardwareHarness({
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
    child: const MaterialApp(home: MobileHardwareSelectionScreen()),
  ),
);

Widget _ledgerHarness({
  required LedgerMobileBleService ble,
  required LedgerAccountConnector connector,
  LedgerOperationCanceller? cancel,
  double textScale = 1,
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
          final args =
              mobileOnboardingPayload(state.extra)! as LedgerBirthdayArgs;
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
      ledgerOperationCancellerProvider.overrideWithValue(cancel ?? () async {}),
      ledgerAppReadinessStateProvider.overrideWith(
        _FakeReadinessController.new,
      ),
    ],
    child: RepaintBoundary(
      key: _captureKey,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: AppTheme(
            data: AppThemeData.light,
            child: MobileOnboardingProgressFrame(child: child!),
          ),
        ),
      ),
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
  LedgerAppReadinessState build() =>
      const LedgerAppReadinessState.ready('3.10.0');
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
  Future<void>? pendingDisconnect;
  int? failDisconnectOnCall;
  Object? disconnectFailure;
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
    if (pendingDisconnect != null) await pendingDisconnect;
    if (disconnectCalls == failDisconnectOnCall) {
      throw disconnectFailure ?? StateError('disconnect cleanup');
    }
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
