import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/widgets/app_pane_modal_overlay.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_text_field.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_connect_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_setup_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart' as rust_ledger;

void main() {
  testWidgets('Linux offers both transports and USB continues to birthday', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        platform: TargetPlatform.linux,
        connector: (index) async => LedgerDeviceAccount(
          ufvk: 'linux-usb-viewing-key',
          seedFingerprint: const [1, 2, 3],
          accountIndex: index,
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
    expect(find.text('USB'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ledger_desktop_ble_connect_button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
    await tester.pumpAndSettle();
    expect(find.text('birthday-linux-usb-viewing-key'), findsOneWidget);
  });

  testWidgets('Windows offers both transports and USB continues to birthday', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        platform: TargetPlatform.windows,
        connector: (index) async => LedgerDeviceAccount(
          ufvk: 'windows-usb-viewing-key',
          seedFingerprint: const [1, 2, 3],
          accountIndex: index,
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
    expect(find.text('USB'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ledger_desktop_ble_connect_button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
    await tester.pumpAndSettle();
    expect(find.text('birthday-windows-usb-viewing-key'), findsOneWidget);
  });

  testWidgets('Windows Bluetooth preserves the app-readiness failure message', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    var accountRequests = 0;
    await tester.pumpWidget(
      _harness(
        platform: TargetPlatform.windows,
        connector: (_) => throw StateError('USB should not be used'),
        bluetoothIdentityConnector: (_) async =>
            throw const LedgerAppReadinessException(
              LedgerAppReadinessFailure.unavailable,
              'Vizor could not resume after opening Zcash. Open Zcash on your Ledger and try again.',
            ),
        bluetoothConnector: (_, _) async {
          accountRequests++;
          throw StateError('UFVK must not be requested before app readiness');
        },
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
    await tester.tap(
      find.byKey(const ValueKey('ledger_desktop_ble_connect_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Vizor could not resume after opening Zcash. Open Zcash on your Ledger and try again.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Vizor could not connect to this Ledger over Bluetooth. Try again.',
      ),
      findsNothing,
    );
    expect(accountRequests, 0);
  });

  testWidgets(
    'Windows Bluetooth duplicate returns to index input and can retry',
    (tester) async {
      await _setDesktopViewport(tester);
      const fingerprint = 'same-ledger-wallet';
      final ble = _FakeLedgerBleService();
      final requestedIndexes = <int>[];
      await tester.pumpWidget(
        _harness(
          platform: TargetPlatform.windows,
          accountState: const AccountState(
            accounts: [
              AccountInfo(
                uuid: 'ledger-0',
                name: 'Existing Ledger',
                order: 0,
                isHardware: true,
                hardwareSignerKind: HardwareSignerKind.ledger,
                zip32AccountIndex: 0,
                ledgerWalletFingerprint: fingerprint,
              ),
            ],
            activeAccountUuid: 'ledger-0',
          ),
          connector: (_) => throw StateError('USB should not be used'),
          bluetoothIdentityConnector: (_) async =>
              const LedgerWalletIdentity(fingerprint: fingerprint),
          bluetoothConnector: (index, device) async {
            requestedIndexes.add(index);
            return LedgerDeviceAccount(
              ufvk: 'bluetooth-index-$index',
              seedFingerprint: const [1, 2, 3],
              accountIndex: index,
              appVersion: '3.9.3',
              transport: LedgerConnectionTransport.bluetooth,
              device: device,
            );
          },
          bleService: ble,
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
      final bluetooth = find.byKey(
        const ValueKey('ledger_desktop_ble_connect_button'),
      );
      final device = find.byKey(
        const ValueKey('ledger_desktop_ble_device_ledger-1'),
      );
      await tester.tap(bluetooth);
      await tester.pumpAndSettle();
      final disconnectsBeforeDuplicate = ble.disconnectCalls;
      await tester.tap(device);
      await tester.pumpAndSettle();

      expect(requestedIndexes, isEmpty);
      expect(ble.disconnectCalls, disconnectsBeforeDuplicate + 1);
      expect(
        find.byKey(const ValueKey('ledger_desktop_ble_connect_dialog')),
        findsNothing,
      );
      expect(
        find.text('Index 0 is already used by this Ledger wallet.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Vizor could not connect to this Ledger over Bluetooth. Try again.',
        ),
        findsNothing,
      );
      final indexInput = find.byKey(
        const ValueKey('ledger_account_index_field'),
      );
      expect(indexInput, findsOneWidget);
      await tester.enterText(indexInput, '1');
      await tester.pumpAndSettle();
      expect(
        find.text('Index 0 is already used by this Ledger wallet.'),
        findsNothing,
      );
      await tester.tap(bluetooth);
      await tester.pumpAndSettle();
      await tester.tap(device);
      await tester.pumpAndSettle();
      expect(requestedIndexes, [1]);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('birthday-bluetooth-index-1'), findsOneWidget);
    },
  );

  testWidgets('Ledger sidebar export preserves 2x pixels and transparency', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await rootBundle.load(
        'assets/illustrations/onboarding_ledger_sidebar.png',
      );
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 512);
      expect(frame.image.height, 860);
      final pixels = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(
        pixels!.getUint8(3),
        0,
        reason: 'Top edge must blend with either sidebar theme',
      );
      frame.image.dispose();
      codec.dispose();
    });
  });

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
    final illustration = tester.widget<Image>(
      find.byKey(const ValueKey('ledger_connect_sidebar_illustration')),
    );
    expect(illustration.image, isA<ExactAssetImage>());
    final asset = illustration.image as ExactAssetImage;
    expect(
      asset.assetName,
      'assets/illustrations/onboarding_ledger_sidebar.png',
    );
    expect(asset.scale, 2);
    expect(illustration.width, 256);
    expect(illustration.height, 430);
    expect(illustration.fit, BoxFit.contain);
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
        label: 'Account index · 0',
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
        label: 'Account index · 0',
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
    await tester.ensureVisible(
      find.byKey(const ValueKey('ledger_connect_button')),
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
      await tester.ensureVisible(
        find.byKey(const ValueKey('ledger_connect_button')),
      );
      final prompt = find.byKey(
        const ValueKey('ledger_connection_preparation'),
      );
      final promptBounds = tester.getRect(prompt);
      final indexField = find.byKey(
        const ValueKey('ledger_account_index_field'),
      );
      final indexBounds = tester.getRect(indexField);
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
        greaterThan(tester.getCenter(find.text('Waiting for Ledger')).dx),
      );
      expect(tester.getRect(prompt), promptBounds);
      expect(tester.getRect(indexField), indexBounds);
      expect(find.text('Check your Ledger'), findsOneWidget);

      expect(
        tester.getSemantics(disclosure),
        isSemantics(
          label: 'Account index · 0',
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

  testWidgets('keeps a calm waiting label while the device is being prepared', (
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

    expect(find.text('Waiting for Ledger'), findsOneWidget);
    expect(find.text('Checking device'), findsNothing);
    expect(find.text('Connect Ledger'), findsWidgets);
    expect(find.text('home-route'), findsNothing);

    pendingAccount.completeError(StateError('request rejected 6985'));
    await tester.pumpAndSettle();
  });

  testWidgets('Linux connection survives focus changes and explains settings', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final pending = Completer<void>();
    final ble = _FakeLedgerBleService()..pendingConnection = pending.future;
    await tester.pumpWidget(
      _harness(
        platform: TargetPlatform.linux,
        connector: (_) => Future.error(StateError('USB should not be used')),
        importer:
            ({
              required name,
              required account,
              required birthdayHeight,
              required profilePictureId,
            }) async =>
                throw StateError('This test must not import an account'),
        bluetoothConnector: (index, device) async => LedgerDeviceAccount(
          ufvk: 'linux-bluetooth-viewing-key',
          seedFingerprint: const [4, 5, 6],
          accountIndex: index,
          appVersion: '3.9.3',
          transport: LedgerConnectionTransport.bluetooth,
          device: device,
        ),
        bleService: ble,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ledger_desktop_ble_connect_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
    );
    await tester.pump();
    expect(
      find.text(
        'Keep your Ledger unlocked. After confirming any pairing prompt, close Bluetooth settings and return to Vizor.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Approve Bluetooth pairing on the device if prompted.'),
      findsNothing,
    );
    final disconnects = ble.disconnectCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(ble.disconnectCalls, disconnects);
    expect(find.text('Connecting to Ledger Flex'), findsOneWidget);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Ledger Flex is ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('imports the approved Ledger account over $platform Bluetooth', (
      tester,
    ) async {
      await _setDesktopViewport(tester);
      final ble = _FakeLedgerBleService();
      LedgerBleDevice? requestedDevice;

      await tester.pumpWidget(
        _harness(
          platform: platform,
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

      await tester.tap(
        find.byKey(const ValueKey('ledger_desktop_ble_connect_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
        findsOneWidget,
      );
      final paneRect = tester.getRect(find.byType(AppDesktopPane));
      final modalPaneRect = tester.getRect(
        find.byKey(const ValueKey('ledger_desktop_ble_modal_pane')),
      );
      final cardRect = tester.getRect(
        find.byKey(const ValueKey('ledger_desktop_ble_connect_dialog')),
      );
      expect(modalPaneRect, paneRect);
      expect(cardRect.center.dx, paneRect.center.dx);
      expect(cardRect.width, 440);
      expect(find.byType(AppPaneModalOverlay), findsOneWidget);
      // The route barrier blocks background interaction without dimming the sidebar.
      for (final barrier in tester.widgetList<ModalBarrier>(
        find.byType(ModalBarrier),
      )) {
        expect(barrier.color?.a ?? 0, 0);
      }
      await tester.tap(
        find.byKey(const ValueKey('ledger_desktop_ble_device_ledger-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ledger Flex is ready'), findsOneWidget);
      expect(
        find.text(
          'Your viewing key was shared. Continue to finish adding your account.',
        ),
        findsOneWidget,
      );
      expect(ble.connectedDeviceId, 'ledger-1');
      expect(ble.openAppCalls, 1);
      expect(requestedDevice?.model, 'Ledger Flex');

      await tester.tap(
        find.byKey(const ValueKey('ledger_desktop_ble_continue')),
      );
      await tester.pumpAndSettle();
      expect(find.text('birthday-uview-bluetooth'), findsOneWidget);
    });
  }

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

      await tester.ensureVisible(
        find.byKey(const ValueKey('ledger_advanced_options_disclosure')),
      );
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
      await tester.ensureVisible(
        find.byKey(const ValueKey('ledger_connect_button')),
      );
      await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Index 2 is already used by this Ledger wallet.'),
        findsOneWidget,
      );

      final indexInput = find.byKey(
        const ValueKey('ledger_account_index_field'),
      );
      final indexMessage = find.byKey(
        const ValueKey('ledger_account_index_message'),
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
      final usb = find.byKey(const ValueKey('ledger_connect_button'));
      final bluetooth = find.byKey(
        const ValueKey('ledger_desktop_ble_connect_button'),
      );
      expect(
        tester.getRect(usb).top,
        greaterThan(tester.getRect(indexMessage).bottom),
      );
      expect(tester.getSize(usb), tester.getSize(bluetooth));
      expect(tester.getRect(usb).top, tester.getRect(bluetooth).top);
      expect(
        tester.getRect(usb).right,
        lessThan(tester.getRect(bluetooth).left),
      );
      expect(
        tester.widget<AppButton>(usb).variant,
        tester.widget<AppButton>(bluetooth).variant,
      );
      expect(
        (tester.widget<AppButton>(usb).leading! as AppIcon).name,
        AppIcons.usb,
      );
      expect(
        (tester.widget<AppButton>(bluetooth).leading! as AppIcon).name,
        AppIcons.bluetooth,
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

    await tester.ensureVisible(
      find.byKey(const ValueKey('ledger_connect_button')),
    );
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
  TargetPlatform platform = TargetPlatform.macOS,
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
      ledgerTargetPlatformProvider.overrideWithValue(platform),
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
  Future<void>? pendingConnection;

  @override
  Future<void> cancelSigning() async {}

  @override
  Future<void> connect(LedgerBleDevice device) async {
    await pendingConnection;
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
    return const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.3');
  }

  @override
  Future<void> stopDiscovery() async {}
}
