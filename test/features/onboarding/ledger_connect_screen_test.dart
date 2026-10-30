import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/legacy_material_theme.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_pane_modal_overlay.dart';
import 'package:zcash_wallet/src/core/widgets/app_text_field.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_failure_guidance.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_procedure.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_modal_content.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_connect_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_setup_args.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart' as rust_ledger;

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  testWidgets(
    'connection and failure stay centered inside the onboarding pane',
    (tester) async {
      await _setDesktopViewport(tester);
      final pending = Completer<LedgerDeviceAccount>();
      await tester.pumpWidget(
        _harness(
          connector: (_) => pending.future,
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
      final pane = tester.getRect(find.byType(AppDesktopPane));
      final connect = find.byKey(const ValueKey('ledger_connect_button'));
      await tester.tap(connect);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final modal = find.byType(LedgerModalContent);
      expect(tester.getCenter(modal).dx, closeTo(pane.center.dx, 0.1));
      expect(tester.getRect(find.byType(AppPaneModalOverlay)), pane);

      pending.completeError(StateError('USB device unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Could not connect Ledger'), findsOneWidget);
      expect(tester.getCenter(modal).dx, closeTo(pane.center.dx, 0.1));
      expect(tester.getRect(find.byType(AppPaneModalOverlay)), pane);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(modal, findsNothing);
      expect(tester.widget<AppButton>(connect).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pane dismissal drains the request and ignores a late account', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final pending = Completer<LedgerDeviceAccount>();
    final stopped = Completer<void>();
    var cancellations = 0;
    await tester.pumpWidget(
      _harness(
        connector: (_) => pending.future,
        canceller: () async {
          cancellations++;
          await stopped.future;
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
    final connect = find.byKey(const ValueKey('ledger_connect_button'));
    await tester.tap(connect);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final pane = tester.getRect(find.byType(AppDesktopPane));
    await tester.tapAt(pane.topLeft + const Offset(12, 12));
    await tester.pump();
    expect(cancellations, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Cancelling request'), findsOneWidget);
    expect(cancellations, 1);
    expect(tester.widget<AppButton>(connect).onPressed, isNull);

    pending.complete(
      const LedgerDeviceAccount(
        ufvk: 'late-account',
        seedFingerprint: [1],
        accountIndex: 0,
        appVersion: '3.9.4',
      ),
    );
    await tester.pump();
    expect(find.text('birthday-late-account'), findsNothing);
    stopped.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LedgerModalContent), findsNothing);
    expect(tester.widget<AppButton>(connect).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bluetooth compatibility opens from its own keyboard action', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    var connections = 0;
    await tester.pumpWidget(
      _harness(
        connector: (_) async {
          connections++;
          throw StateError('Help must not start a connection');
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
    final usb = find.byKey(const ValueKey('ledger_transport_usb'));
    final bluetooth = find.byKey(const ValueKey('ledger_transport_bluetooth'));
    final help = find.byKey(const ValueKey('ledger_supported_devices'));
    final models = find.text('Nano X · Flex · Stax · Nano Gen5');
    final check = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.name == AppIcons.check,
    );
    final usbLabelPosition = tester.getTopLeft(find.text('USB'));
    final bluetoothLabelPosition = tester.getTopLeft(find.text('Bluetooth'));
    expect(help, findsNothing);
    expect(models, findsNothing);
    expect(tester.getSize(usb), tester.getSize(bluetooth));
    expect(find.descendant(of: usb, matching: check), findsOneWidget);
    expect(find.descendant(of: bluetooth, matching: check), findsNothing);

    await tester.tap(bluetooth);
    await tester.pumpAndSettle();
    expect(find.descendant(of: usb, matching: check), findsNothing);
    expect(find.descendant(of: bluetooth, matching: check), findsOneWidget);
    expect(tester.getTopLeft(find.text('USB')).dx, usbLabelPosition.dx);
    expect(
      tester.getTopLeft(find.text('Bluetooth')).dx,
      bluetoothLabelPosition.dx,
    );
    expect(help, findsOneWidget);
    expect(models, findsNothing);
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(models, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(models, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(models, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(models, findsNothing);

    await tester.tap(help);
    await tester.pumpAndSettle();
    await tester.tap(find.text('On your Ledger'));
    await tester.pumpAndSettle();
    expect(models, findsNothing);
    await tester.tap(help);
    await tester.pumpAndSettle();
    await tester.tap(usb);
    await tester.pumpAndSettle();
    expect(find.descendant(of: usb, matching: check), findsOneWidget);
    expect(find.descendant(of: bluetooth, matching: check), findsNothing);
    expect(help, findsNothing);
    expect(models, findsNothing);
    await tester.tap(bluetooth);
    await tester.pumpAndSettle();
    expect(help, findsOneWidget);
    expect(models, findsNothing);
    expect(connections, 0);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('$platform imports over USB without a transport picker', (
      tester,
    ) async {
      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _harness(
          platform: platform,
          connector: (_) async => const LedgerDeviceAccount(
            ufvk: 'usb-account',
            seedFingerprint: [1],
            accountIndex: 0,
            appVersion: '3.9.3',
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
      expect(find.byKey(const ValueKey('ledger_transport_usb')), findsNothing);
      expect(
        find.byKey(const ValueKey('ledger_transport_bluetooth')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ledger_supported_devices')),
        findsNothing,
      );
      expect(
        find.text('1. Unlock with your PIN.\n\n2. Connect with a USB cable.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
      await tester.pumpAndSettle();
      expect(find.text('birthday-usb-account'), findsOneWidget);
    });
  }

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

  testWidgets(
    'invalid account index does not add scroll at the desktop minimum',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 720));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await loadFigmaCompareFonts();
      var connections = 0;
      await tester.pumpWidget(
        _harness(
          connector: (_) async {
            connections++;
            throw StateError('Invalid index must not connect');
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
        find.byKey(const ValueKey('ledger_transport_bluetooth')),
      );
      final disclosure = find.byKey(
        const ValueKey('ledger_advanced_options_disclosure'),
      );
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('ledger_account_index_field'));
      final connect = find.byKey(const ValueKey('ledger_connect_button'));
      final bodyPosition = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(SingleChildScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      final fieldBefore = tester.getRect(field);
      final buttonBefore = tester.getRect(connect);
      expect(bodyPosition.maxScrollExtent, 0);

      await tester.enterText(field, '101');
      await tester.pumpAndSettle();
      expect(
        find.text('Account index must be between 0 and 100.'),
        findsOneWidget,
      );
      await tester.tap(connect);
      await tester.pumpAndSettle();
      expect(bodyPosition.maxScrollExtent, 0);
      expect(tester.getRect(field), fieldBefore);
      expect(tester.getRect(connect), buttonBefore);
      expect(
        find.text('Account index must be between 0 and 100.'),
        findsOneWidget,
      );
      expect(
        tester.widget<AppTextField>(field).tone,
        AppTextFieldTone.destructive,
      );

      await tester.enterText(field, '100');
      await tester.pumpAndSettle();
      expect(
        find.text('Account index must be between 0 and 100.'),
        findsNothing,
      );
      expect(tester.widget<AppTextField>(field).tone, AppTextFieldTone.neutral);
      expect(bodyPosition.maxScrollExtent, 0);

      await tester.enterText(field, '101');
      await tester.tap(connect);
      await tester.pumpAndSettle();
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      expect(
        find.text('Account index must be between 0 and 100.'),
        findsNothing,
      );
      await tester.tap(connect);
      await tester.pumpAndSettle();
      expect(field, findsOneWidget);
      expect(
        find.text('Account index must be between 0 and 100.'),
        findsOneWidget,
      );
      expect(bodyPosition.maxScrollExtent, 0);
      expect(tester.getRect(connect), buttonBefore);
      expect(connections, 0);
      expect(tester.takeException(), isNull);
    },
  );

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
    for (final invalid in ['101', '102', '', '999999999999999999999999']) {
      await tester.enterText(
        find.byKey(const ValueKey('ledger_account_index_field')),
        invalid,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Account index must be between 0 and 100.'),
        findsOneWidget,
      );
      expect(requestedIndex, isNull);
      await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
      await tester.pumpAndSettle();
      expect(
        find.text('Account index must be between 0 and 100.'),
        findsOneWidget,
      );
      expect(requestedIndex, isNull);
    }
    for (final valid in ['0', '100']) {
      await tester.enterText(
        find.byKey(const ValueKey('ledger_account_index_field')),
        valid,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Account index must be between 0 and 100.'),
        findsNothing,
      );
      expect(requestedIndex, isNull);
    }
    await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
    await tester.pumpAndSettle();

    expect(find.text('birthday-uview-ledger-100'), findsOneWidget);
    expect(requestedIndex, 100);
  });

  testWidgets(
    'keeps expanded advanced options stable and disabled while busy',
    (tester) async {
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
      expect(busyButton.onPressed, isNull);
      expect(busyButton.trailing, isNull);
      final procedure = tester.widget<LedgerProcedure>(
        find.byType(LedgerProcedure),
      );
      expect(procedure.currentStep, 1);
      expect(procedure.steps[procedure.currentStep].busy, isTrue);
      expect(find.text('Vizor is checking the Zcash app.'), findsOneWidget);
      expect(
        tester
            .widget<AppTextField>(
              find.byKey(const ValueKey('ledger_account_index_field')),
            )
            .enabled,
        isFalse,
      );

      pendingAccount.completeError(StateError(_deviceRejected));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('shows an actionable device rejection without importing', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    var importCalls = 0;

    await tester.pumpWidget(
      _harness(
        connector: (_) => Future.error(StateError(_deviceRejected)),
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
      find.text('Sharing was declined on Ledger. Try again when you’re ready.'),
      findsOneWidget,
    );
    expect(importCalls, 0);
    expect(find.text('home-route'), findsNothing);
  });

  testWidgets('status 0x6a80 does not read as a device rejection', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    var importCalls = 0;

    await tester.pumpWidget(
      _harness(
        connector: (_) => Future.error(
          StateError(
            'ledger_status_6a80: Ledger rejected the PCZT data or key path',
          ),
        ),
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

    expect(find.text(kLedgerViewingKeyRequestRejectedMessage), findsOneWidget);
    expect(find.textContaining('rejected on your Ledger'), findsNothing);
    expect(importCalls, 0);
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

    expect(find.text('Vizor is checking the Zcash app.'), findsOneWidget);
    expect(find.text('Connect Ledger'), findsWidgets);
    expect(find.text('home-route'), findsNothing);

    pendingAccount.completeError(StateError(_deviceRejected));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'macOS Bluetooth picker preserves pairing guidance from readiness',
    (tester) async {
      await _setDesktopViewport(tester);
      const error = LedgerMobileException(
        LedgerMobileFailure.pairingInvalid,
        'pairing diagnostic',
      );
      await tester.pumpWidget(
        _harness(
          connector: (_) => throw StateError('USB must not run'),
          bluetoothConnector: (_, _) async =>
              throw const LedgerAppReadinessException(
                LedgerAppReadinessFailure.disconnected,
                'wrapper',
                cause: error,
              ),
          importer:
              ({
                required name,
                required account,
                required birthdayHeight,
                required profilePictureId,
              }) async {},
          bleService: _FakeLedgerBleService(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ledger_transport_bluetooth')),
      );
      await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text(ledgerFailureGuidance(error)!.message), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    },
  );

  for (final transport in LedgerConnectionTransport.values) {
    testWidgets('auto-connect can publish readiness over ${transport.name}', (
      tester,
    ) async {
      final account = Completer<LedgerDeviceAccount>();
      late ProviderContainer container;
      Object? readinessError;
      var calls = 0;
      const approved = LedgerDeviceAccount(
        ufvk: 'auto-connect-ready',
        seedFingerprint: [1],
        accountIndex: 0,
        appVersion: '3.9.4',
      );
      addTearDown(() {
        if (!account.isCompleted) account.complete(approved);
      });
      Future<LedgerDeviceAccount> connect(int index) async {
        calls++;
        try {
          // ensureReady publishes this state before its first native await.
          container
              .read(ledgerAppReadinessStateProvider.notifier)
              .update(
                const LedgerAppReadinessState.inProgress(
                  LedgerAppReadinessPhase.checkingDevice,
                ),
              );
        } catch (error) {
          readinessError = error;
          rethrow;
        }
        return account.future;
      }

      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _harness(
          connector: connect,
          bluetoothConnector: (index, _) => connect(index),
          bleService: _FakeLedgerBleService(),
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
      container = ProviderScope.containerOf(
        tester.element(find.byType(LedgerConnectScreen)),
      );
      if (transport == LedgerConnectionTransport.bluetooth) {
        await tester.tap(
          find.byKey(const ValueKey('ledger_transport_bluetooth')),
        );
      }
      await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (transport == LedgerConnectionTransport.bluetooth) {
        await tester.tap(
          find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(calls, 1);
      expect(readinessError, isNull);
      final procedure = tester.widget<LedgerProcedure>(
        find.byType(LedgerProcedure),
      );
      expect(procedure.currentStep, 1);
      expect(procedure.steps[1].busy, isTrue);
      expect(find.text('Could not connect Ledger'), findsNothing);
      account.complete(approved);
      await tester.pumpAndSettle();
      expect(find.text('birthday-auto-connect-ready'), findsOneWidget);
    });

    testWidgets('app-opening rejection retries Open Zcash over ${transport.name}', (
      tester,
    ) async {
      final approval = Completer<LedgerDeviceAccount>();
      var calls = 0;
      Future<LedgerDeviceAccount> connect(int index) {
        calls++;
        if (calls == 1) {
          return Future.error(
            const LedgerAppReadinessException(
              LedgerAppReadinessFailure.rejected,
              'The request was rejected on your Ledger. Try again when ready.',
              cause: LedgerMobileException(
                LedgerMobileFailure.rejected,
                'App opening rejected',
              ),
            ),
          );
        }
        return approval.future;
      }

      addTearDown(() {
        if (!approval.isCompleted) {
          approval.completeError(StateError(_deviceRejected));
        }
      });
      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _harness(
          connector: connect,
          bluetoothConnector: (index, _) => connect(index),
          bleService: _FakeLedgerBleService(),
          readiness: const LedgerAppReadinessState.failed(
            failure: LedgerAppReadinessFailure.rejected,
            message:
                'The request was rejected on your Ledger. Try again when ready.',
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
      if (transport == LedgerConnectionTransport.bluetooth) {
        await tester.tap(
          find.byKey(const ValueKey('ledger_transport_bluetooth')),
        );
      }
      await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
      await tester.pumpAndSettle();
      if (transport == LedgerConnectionTransport.bluetooth) {
        await tester.tap(
          find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
        );
        await tester.pumpAndSettle();
      }
      var procedure = tester.widget<LedgerProcedure>(
        find.byType(LedgerProcedure),
      );
      expect(procedure.currentStep, 1);
      expect(procedure.steps[1].busy, isFalse);
      expect(
        find.text(
          'Opening Zcash was declined on Ledger. Try again when you’re ready.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Sharing was declined on Ledger. Try again when you’re ready.',
        ),
        findsNothing,
      );
      await tester.tap(find.text('Try again'));
      await tester.pump();
      procedure = tester.widget<LedgerProcedure>(find.byType(LedgerProcedure));
      expect(procedure.currentStep, 1);
      expect(procedure.steps[1].busy, isTrue);
      final readiness =
          ProviderScope.containerOf(
                tester.element(find.byType(LedgerConnectScreen)),
              ).read(ledgerAppReadinessStateProvider.notifier)
              as _FakeReadinessController;
      readiness.publish(
        const LedgerAppReadinessState.inProgress(
          LedgerAppReadinessPhase.confirmOpening,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Confirm opening Zcash on Ledger.'), findsOneWidget);
      readiness.publish(const LedgerAppReadinessState.ready('3.9.4'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      procedure = tester.widget<LedgerProcedure>(find.byType(LedgerProcedure));
      expect(procedure.currentStep, 2);
      expect(
        find.text('Approve sharing the viewing key for Account #0.'),
        findsOneWidget,
      );
      expect(calls, 2);
      approval.complete(
        const LedgerDeviceAccount(
          ufvk: 'app-open-retry',
          seedFingerprint: [1],
          accountIndex: 0,
          appVersion: '3.9.4',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('birthday-app-open-retry'), findsOneWidget);
    });
  }

  for (final cancelInstead in [false, true]) {
    testWidgets(
      'cleanup retry retains the requested destination (cancel: $cancelInstead)',
      (tester) async {
        final oldAccount = Completer<LedgerDeviceAccount>();
        final ble = _FakeLedgerBleService()
          ..devices = const [
            LedgerBleDevice(id: 'ledger-1', name: 'Ledger Flex', model: 'Flex'),
            LedgerBleDevice(id: 'ledger-2', name: 'Ledger Stax', model: 'Stax'),
          ];
        final requests = <String>[];
        var cancels = 0;
        addTearDown(() {
          if (!oldAccount.isCompleted) {
            oldAccount.completeError(StateError(_deviceRejected));
          }
        });
        await _setDesktopViewport(tester);
        await tester.pumpWidget(
          _harness(
            connector: (_) => Future.error(StateError('Unexpected USB')),
            bluetoothConnector: (index, device) {
              requests.add(device.id);
              return device.id == 'ledger-1'
                  ? oldAccount.future
                  : Future.value(
                      LedgerDeviceAccount(
                        ufvk: 'other-ledger',
                        seedFingerprint: const [2],
                        accountIndex: index,
                        appVersion: '3.9.4',
                        transport: LedgerConnectionTransport.bluetooth,
                        device: device,
                      ),
                    );
            },
            bleService: ble,
            canceller: () async {
              cancels++;
              if (!oldAccount.isCompleted) {
                oldAccount.completeError(StateError(_deviceRejected));
              }
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
          find.byKey(const ValueKey('ledger_transport_bluetooth')),
        );
        await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        ble.disconnectFailures = 1;
        await tester.tap(find.bySemanticsLabel('Choose another Ledger'));
        await tester.pumpAndSettle();
        expect(cancels, 1);
        expect(
          find.text('Could not finish cleanup. Try again.'),
          findsOneWidget,
        );
        await tester.tap(find.text(cancelInstead ? 'Cancel' : 'Try again'));
        await tester.pumpAndSettle();
        expect(cancels, 2);
        if (cancelInstead) {
          expect(find.text('Find Ledger'), findsNothing);
          expect(
            find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-2')),
            findsNothing,
          );
          expect(requests, ['ledger-1']);
          return;
        }
        expect(
          find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-2')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-2')),
        );
        await tester.pumpAndSettle();
        expect(requests, ['ledger-1', 'ledger-2']);
        expect(find.text('birthday-other-ledger'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'viewing-key rejection retries the approval step without resetting completed steps',
    (tester) async {
      final approval = Completer<LedgerDeviceAccount>();
      var attempts = 0;
      addTearDown(() {
        if (!approval.isCompleted) {
          approval.completeError(StateError(_deviceRejected));
        }
      });
      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _harness(
          connector: (_) {
            attempts++;
            return attempts == 1
                ? Future.error(StateError(_deviceRejected))
                : approval.future;
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
      var procedure = tester.widget<LedgerProcedure>(
        find.byType(LedgerProcedure),
      );
      expect(procedure.currentStep, 2);
      expect(procedure.steps[2].busy, isFalse);
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 300));
      procedure = tester.widget<LedgerProcedure>(find.byType(LedgerProcedure));
      expect(procedure.currentStep, 2);
      expect(procedure.steps[2].busy, isTrue);
      final readiness =
          ProviderScope.containerOf(
                tester.element(find.byType(LedgerConnectScreen)),
              ).read(ledgerAppReadinessStateProvider.notifier)
              as _FakeReadinessController;
      readiness.publish(
        const LedgerAppReadinessState.inProgress(
          LedgerAppReadinessPhase.confirmOpening,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      procedure = tester.widget<LedgerProcedure>(find.byType(LedgerProcedure));
      expect(procedure.currentStep, 1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Confirm opening Zcash on Ledger.'), findsOneWidget);
      readiness.publish(const LedgerAppReadinessState.ready('3.9.4'));
      await tester.pump(const Duration(milliseconds: 300));
      procedure = tester.widget<LedgerProcedure>(find.byType(LedgerProcedure));
      expect(procedure.currentStep, 2);
      approval.complete(
        const LedgerDeviceAccount(
          ufvk: 'approved-retry',
          seedFingerprint: [1],
          accountIndex: 0,
          appVersion: '3.9.4',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('birthday-approved-retry'), findsOneWidget);
    },
  );

  testWidgets(
    'choosing another Ledger drains the old request and ignores its late account',
    (tester) async {
      final oldAccount = Completer<LedgerDeviceAccount>();
      final cancel = Completer<void>();
      final ble = _FakeLedgerBleService()
        ..devices = const [
          LedgerBleDevice(
            id: 'ledger-1',
            name: 'Ledger Flex',
            model: 'Ledger Flex',
          ),
          LedgerBleDevice(
            id: 'ledger-2',
            name: 'Ledger Stax',
            model: 'Ledger Stax',
          ),
        ];
      var cancelled = 0;
      final requests = <String>[];
      addTearDown(() {
        if (!cancel.isCompleted) cancel.complete();
        if (!oldAccount.isCompleted) {
          oldAccount.completeError(StateError(_deviceRejected));
        }
      });
      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _harness(
          connector: (_) async => throw StateError('USB unexpected'),
          bluetoothConnector: (index, device) {
            requests.add(device.id);
            return device.id == 'ledger-1'
                ? oldAccount.future
                : Future.error(StateError(_deviceRejected));
          },
          bleService: ble,
          canceller: () async {
            cancelled++;
            await cancel.future;
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
        find.byKey(const ValueKey('ledger_transport_bluetooth')),
      );
      await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
      );
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Choose another Ledger'));
      await tester.pump();
      expect(cancelled, 1);
      expect(find.text('Cancelling request'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-2')),
        findsNothing,
      );
      cancel.complete();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-2')),
        findsNothing,
      );
      oldAccount.complete(
        const LedgerDeviceAccount(
          ufvk: 'late-account',
          seedFingerprint: [1],
          accountIndex: 0,
          appVersion: '3.9.4',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('birthday-late-account'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-2')),
      );
      await tester.pumpAndSettle();
      expect(requests, ['ledger-1', 'ledger-2']);
      expect(
        find.text(
          'Sharing was declined on Ledger. Try again when you’re ready.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'back from discovery waits for scan stop and preserves account options',
    (tester) async {
      final stopped = Completer<void>();
      final ble = _FakeLedgerBleService();
      var cancelled = 0;
      addTearDown(() {
        if (!stopped.isCompleted) stopped.complete();
      });
      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _harness(
          connector: (_) async => throw StateError('USB unexpected'),
          bleService: ble,
          canceller: () async => cancelled++,
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
        '7',
      );
      await tester.tap(
        find.byKey(const ValueKey('ledger_transport_bluetooth')),
      );
      await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
      await tester.pumpAndSettle();
      ble.stopGate = stopped.future;
      await tester.tap(
        find.bySemanticsLabel('Choose another Ledger').evaluate().isEmpty
            ? find.bySemanticsLabel('Choose connection')
            : find.bySemanticsLabel('Choose another Ledger'),
      );
      await tester.pump();
      expect(find.text('Stopping search'), findsOneWidget);
      expect(cancelled, 0);
      stopped.complete();
      await tester.pumpAndSettle();
      expect(find.text('Find Ledger'), findsNothing);
      expect(
        tester
            .widget<AppTextField>(
              find.byKey(const ValueKey('ledger_account_index_field')),
            )
            .controller!
            .text,
        '7',
      );
    },
  );

  testWidgets('captures implemented desktop Ledger connection states', (
    tester,
  ) async {
    const output = String.fromEnvironment('LEDGER_IMPL_CAPTURE_DIR');
    if (output.isEmpty) return;
    Directory(output).createSync(recursive: true);
    await loadFigmaCompareFonts();
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    for (final theme in [AppThemeData.light, AppThemeData.dark]) {
      for (final scene in [
        'start',
        'usb-only-windows',
        'usb-only-linux',
        'usb-hover',
        'bluetooth-hover',
        'bluetooth',
        'supported-devices',
        'supported-devices-large-text',
        'advanced',
        'advanced-hover',
        'advanced-invalid',
        'advanced-corrected',
        'advanced-invalid-large-text',
        'devices',
        'opening',
        'opening-declined',
        'opening-retry',
        'approval',
        'declined',
        'failed',
        'large-text',
        'advanced-large-text',
      ]) {
        final pending = Completer<LedgerDeviceAccount>();
        var attempts = 0;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        const boundary = ValueKey('ledger_capture');
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: _harness(
              theme: theme,
              platform: switch (scene) {
                'usb-only-windows' => TargetPlatform.windows,
                'usb-only-linux' => TargetPlatform.linux,
                _ => TargetPlatform.macOS,
              },
              textScaler: scene.endsWith('large-text')
                  ? const TextScaler.linear(2)
                  : TextScaler.noScaling,
              connector: (_) {
                attempts++;
                if (scene == 'failed') {
                  return Future.error(StateError('USB device unavailable'));
                }
                if (scene == 'declined') {
                  return Future.error(StateError(_deviceRejected));
                }
                if ((scene == 'opening-declined' || scene == 'opening-retry') &&
                    attempts == 1) {
                  return Future.error(
                    const LedgerAppReadinessException(
                      LedgerAppReadinessFailure.rejected,
                      'App opening rejected',
                      cause: LedgerMobileException(
                        LedgerMobileFailure.rejected,
                        'App opening rejected',
                      ),
                    ),
                  );
                }
                return pending.future;
              },
              bleService: _FakeLedgerBleService(),
              readiness: scene == 'approval'
                  ? const LedgerAppReadinessState.ready('3.9.4')
                  : const LedgerAppReadinessState.inProgress(
                      LedgerAppReadinessPhase.confirmOpening,
                    ),
              importer:
                  ({
                    required name,
                    required account,
                    required birthdayHeight,
                    required profilePictureId,
                  }) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (scene.startsWith('usb-only-')) {
          expect(
            find.byKey(const ValueKey('ledger_transport_usb')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('ledger_transport_bluetooth')),
            findsNothing,
          );
        } else if (scene == 'bluetooth' ||
            scene.startsWith('supported-devices')) {
          await tester.tap(
            find.byKey(const ValueKey('ledger_transport_bluetooth')),
          );
          await tester.pumpAndSettle();
          if (scene.startsWith('supported-devices')) {
            await tester.tap(
              find.byKey(const ValueKey('ledger_supported_devices')),
            );
            await tester.pumpAndSettle();
            expect(
              find.text('Nano X · Flex · Stax · Nano Gen5'),
              findsOneWidget,
            );
          }
        } else if (scene.startsWith('advanced')) {
          final invalidIndex =
              scene.contains('invalid') || scene == 'advanced-corrected';
          if (invalidIndex) {
            await tester.tap(
              find.byKey(const ValueKey('ledger_transport_bluetooth')),
            );
          }
          await tester.ensureVisible(
            find.byKey(const ValueKey('ledger_advanced_options_disclosure')),
          );
          await tester.tap(
            find.byKey(const ValueKey('ledger_advanced_options_disclosure')),
          );
          await tester.pumpAndSettle();
          if (invalidIndex) {
            final field = find.byKey(
              const ValueKey('ledger_account_index_field'),
            );
            await tester.enterText(field, '101');
            await tester.pumpAndSettle();
            expect(
              find.text('Account index must be between 0 and 100.'),
              findsOneWidget,
            );
            if (scene == 'advanced-corrected') {
              await tester.enterText(field, '100');
              await tester.pumpAndSettle();
            }
          }
        } else if (scene == 'devices') {
          await tester.tap(
            find.byKey(const ValueKey('ledger_transport_bluetooth')),
          );
          await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
          await tester.pumpAndSettle();
        } else if (![
          'start',
          'usb-hover',
          'bluetooth-hover',
          'large-text',
        ].contains(scene)) {
          await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          if (scene == 'opening-retry') {
            await tester.tap(find.text('Try again'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
          }
          if (scene == 'failed') {
            expect(find.text('Could not connect Ledger'), findsOneWidget);
          } else {
            expect(find.byType(LedgerProcedure), findsOneWidget);
            expect(
              find.text(
                scene == 'declined'
                    ? 'Sharing was declined on Ledger. Try again when you’re ready.'
                    : scene == 'opening-declined'
                    ? 'Opening Zcash was declined on Ledger. Try again when you’re ready.'
                    : scene == 'approval'
                    ? 'Approve sharing the viewing key for Account #0.'
                    : 'Confirm opening Zcash on Ledger.',
              ),
              findsOneWidget,
            );
          }
        }
        TestGesture? mouse;
        if (scene.endsWith('-hover')) {
          mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(
            tester.getCenter(
              find.byKey(
                ValueKey(switch (scene) {
                  'usb-hover' => 'ledger_transport_usb',
                  'bluetooth-hover' => 'ledger_transport_bluetooth',
                  _ => 'ledger_advanced_options_disclosure',
                }),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(boundary),
          matchesGoldenFile(
            File(
              '$output/connection-$scene${theme == AppThemeData.dark ? '-dark' : ''}.png',
            ).uri,
          ),
        );
        await mouse?.removePointer();
        if (!pending.isCompleted) {
          if (scene == 'opening' ||
              scene == 'opening-retry' ||
              scene == 'approval') {
            pending.completeError(StateError(_deviceRejected));
          } else {
            pending.complete(
              const LedgerDeviceAccount(
                ufvk: 'unused-capture',
                seedFingerprint: [1],
                accountIndex: 0,
                appVersion: '3.9.4',
              ),
            );
          }
        }
        await tester.pump(const Duration(milliseconds: 400));
      }
    }
  }, tags: ['figma-capture']);

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
            appVersion: '3.9.3',
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

    await tester.tap(find.byKey(const ValueKey('ledger_transport_bluetooth')));
    await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
    );
    await tester.pumpAndSettle();

    expect(ble.connectedDeviceId, 'ledger-1');
    expect(ble.openAppCalls, 1);
    expect(requestedDevice?.model, 'Ledger Flex');
    expect(find.text('birthday-uview-bluetooth'), findsOneWidget);
  });

  for (final (error, message) in const [
    (
      _deviceRejected,
      'Sharing was declined on Ledger. Try again when you’re ready.',
    ),
    (
      'ledger_status_6a80: Ledger rejected the PCZT data or key path',
      kLedgerViewingKeyRequestRejectedMessage,
    ),
  ]) {
    testWidgets(
      'macOS Bluetooth probe explains ${error.substring(0, 18)} by its code',
      (tester) async {
        await _setDesktopViewport(tester);
        await tester.pumpWidget(
          _harness(
            connector: (_) =>
                Future.error(StateError('USB should not be used')),
            bluetoothConnector: (_, _) => Future.error(StateError(error)),
            importer:
                ({
                  required name,
                  required account,
                  required birthdayHeight,
                  required profilePictureId,
                }) async {},
            bleService: _FakeLedgerBleService(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('ledger_transport_bluetooth')),
        );
        await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
        );
        await tester.pumpAndSettle();

        expect(find.text(message), findsOneWidget);
        expect(find.textContaining('ledger_status_'), findsNothing);
      },
    );
  }
}

const _deviceRejected =
    'ledger_status_6985: Ledger request was rejected or the PCZT was not finalized';

Widget _harness({
  required LedgerAccountConnector connector,
  required LedgerAccountImporter importer,
  LedgerBluetoothAccountConnector? bluetoothConnector,
  LedgerAppReadinessState readiness = const LedgerAppReadinessState.idle(),
  LedgerMobileBleService? bleService,
  LedgerOperationCanceller? canceller,
  TargetPlatform platform = TargetPlatform.macOS,
  AppThemeData theme = AppThemeData.light,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final router = GoRouter(
    initialLocation: '/onboarding/ledger',
    routes: [
      GoRoute(
        path: '/onboarding/ledger',
        builder: (_, _) => const LedgerConnectScreen(),
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
      ledgerTargetPlatformProvider.overrideWithValue(platform),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
      ledgerAccountConnectorProvider.overrideWithValue(connector),
      ledgerBluetoothAccountConnectorProvider.overrideWithValue(
        bluetoothConnector ??
            (_, _) => Future.error(StateError('Bluetooth should not be used')),
      ),
      ledgerAccountImporterProvider.overrideWithValue(importer),
      ledgerOperationCancellerProvider.overrideWithValue(
        canceller ?? () async {},
      ),
      if (bleService != null)
        ledgerMobileBleServiceProvider.overrideWithValue(bleService),
      ledgerAppReadinessStateProvider.overrideWith(
        () => _FakeReadinessController(readiness),
      ),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: buildLegacyLightTheme(),
      darkTheme: buildLegacyDarkTheme(),
      themeMode: theme == AppThemeData.dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      builder: (context, child) => AppTheme(
        data: theme,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
      ),
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

class _FakeReadinessController extends LedgerAppReadinessController {
  _FakeReadinessController(this.initialState);

  final LedgerAppReadinessState initialState;

  void publish(LedgerAppReadinessState next) => state = next;

  @override
  LedgerAppReadinessState build() => initialState;
}

class _FakeLedgerBleService implements LedgerMobileBleService {
  @override
  String? connectedDeviceId;
  int disconnectCalls = 0;
  int disconnectFailures = 0;
  int openAppCalls = 0;
  int stopCalls = 0;
  Future<void>? stopGate;
  List<LedgerBleDevice> devices = const [
    LedgerBleDevice(id: 'ledger-1', name: 'Ledger Flex', model: 'Ledger Flex'),
  ];

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
    if (disconnectFailures > 0) {
      disconnectFailures--;
      throw StateError('Native disconnect failed');
    }
    connectedDeviceId = null;
  }

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() async* {
    yield LedgerDevicesDiscovered(devices);
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
    return const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.3');
  }

  @override
  Future<void> stopDiscovery() async {
    stopCalls++;
    await stopGate;
  }
}
