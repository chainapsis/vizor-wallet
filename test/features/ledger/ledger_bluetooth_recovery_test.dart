import 'dart:async';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_access_recovery_modal.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_modal_content.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_bluetooth_access.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_request.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_bluetooth_recovery.dart';

class _Access implements LedgerMobileBleService, LedgerBluetoothAccess {
  LedgerBluetoothAccessStatus status = const LedgerBluetoothAccessStatus(
    LedgerBluetoothPermission.requestable,
  );
  Completer<bool>? permissionPending;
  int requests = 0;
  int reads = 0;
  int settings = 0;
  bool opensSettings = true;
  Completer<bool>? settingsPending;
  Completer<LedgerBluetoothAccessStatus>? pending;
  @override
  Future<LedgerBluetoothAccessStatus> bluetoothAccessStatus() async {
    reads++;
    return pending?.future ?? status;
  }

  @override
  Future<bool> requestPermissions() async {
    requests++;
    return permissionPending?.future ?? false;
  }

  @override
  Future<bool> openBluetoothSettings() async {
    settings++;
    return settingsPending?.future ?? opensSettings;
  }

  // Any accidental discovery, connect or signing call fails the test.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName}');
}

Widget _harness(_Access service, {ProviderContainer? container}) {
  final child = MaterialApp(
    home: AppTheme(
      data: AppThemeData.light,
      child: Center(
        child: SizedBox(
          width: 328,
          child: LedgerBluetoothRecovery(service: service),
        ),
      ),
    ),
  );
  return container == null
      ? ProviderScope(child: child)
      : UncontrolledProviderScope(container: container, child: child);
}

void main() {
  for (final operation in ['status', 'permission', 'settings']) {
    testWidgets('desktop recovery blocks connection changes during $operation', (
      tester,
    ) async {
      final service = _Access();
      if (operation == 'status') {
        service.pending = Completer<LedgerBluetoothAccessStatus>();
      } else if (operation == 'permission') {
        service.permissionPending = Completer<bool>();
      } else {
        service.status = const LedgerBluetoothAccessStatus(
          LedgerBluetoothPermission.settings,
        );
        service.settingsPending = Completer<bool>();
      }
      void completePending() {
        if (service.pending case final pending? when !pending.isCompleted) {
          pending.complete(service.status);
        }
        if (service.permissionPending case final pending?
            when !pending.isCompleted) {
          pending.complete(false);
        }
        if (service.settingsPending case final pending?
            when !pending.isCompleted) {
          pending.complete(false);
        }
      }

      final container = ProviderContainer(
        overrides: [
          ledgerMobileBleServiceProvider.overrideWithValue(service),
          ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
          accountProvider.overrideWith(_AccountsNotifier.new),
        ],
      );
      addTearDown(() async {
        completePending();
        await tester.pump();
        container.dispose();
      });
      var changes = 0;
      var showingRecovery = true;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: StatefulBuilder(
                builder: (context, setState) => Center(
                  child: showingRecovery
                      ? LedgerAccessRecoveryModal(
                          account: _account,
                          onRetry: () {},
                          onClose: () {},
                          onChangeConnection: () => setState(() {
                            changes++;
                            showingRecovery = false;
                          }),
                        )
                      : const Text('Connection options'),
                ),
              ),
            ),
          ),
        ),
      );
      if (operation != 'status') await tester.pumpAndSettle();
      final previousBack = tester
          .widget<LedgerModalContent>(find.byType(LedgerModalContent))
          .onBack;
      if (operation != 'status') {
        expect(previousBack, isNotNull);
        await tester.tap(
          find.text(
            operation == 'permission' ? 'Allow access' : 'Open settings',
          ),
        );
      }
      // A callback captured before the next frame must also respect busy work.
      previousBack?.call();
      await tester.pump();
      expect(changes, 0);
      // The modal refresh is deferred until after the child's busy-state frame.
      await tester.pump();
      expect(service.requests, operation == 'permission' ? 1 : 0);
      expect(service.settings, operation == 'settings' ? 1 : 0);
      expect(find.text('Checking Bluetooth access…'), findsOneWidget);
      expect(
        tester
            .widget<LedgerModalContent>(find.byType(LedgerModalContent))
            .onBack,
        isNull,
      );
      expect(find.bySemanticsLabel('Change connection'), findsNothing);
      expect(find.byType(LedgerAccessRecoveryModal), findsOneWidget);

      completePending();
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Change connection'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Change connection'));
      await tester.pumpAndSettle();
      expect(changes, 1);
      expect(find.text('Connection options'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, tags: ['desktop']);
  }

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      '$platform recovery has one primary action without stored transport controls',
      (tester) async {
        final service = _Access();
        final notifier = _AccountsNotifier();
        var retries = 0;
        final container = ProviderContainer(
          overrides: [
            ledgerMobileBleServiceProvider.overrideWithValue(service),
            ledgerTargetPlatformProvider.overrideWithValue(platform),
            accountProvider.overrideWith(() => notifier),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: AppTheme(
                data: AppThemeData.light,
                child: Center(
                  child: LedgerAccessRecoveryModal(
                    account: _account,
                    onRetry: () => retries++,
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Allow access'), findsOneWidget);
        expect(find.text('Open settings'), findsNothing);
        expect(find.text('Check access'), findsNothing);
        expect(find.text('Try again'), findsNothing);
        expect(find.text('Auto'), findsNothing);
        expect(
          tester
              .widget<AppButton>(find.widgetWithText(AppButton, 'Allow access'))
              .variant,
          AppButtonVariant.primary,
        );
        expect(find.text('USB'), findsNothing);
        expect(find.text('Connection'), findsNothing);
        service.permissionPending = Completer<bool>();
        await tester.tap(find.text('Allow access'));
        await tester.pump();
        service.permissionPending!.complete(false);
        await tester.pumpAndSettle();
        expect(find.text('Open settings'), findsOneWidget);
        expect(retries, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'native access payload preserves radio, location, and platform distinctions',
    () {
      final status = LedgerBluetoothAccessStatus.fromMap({
        'permission': 'granted',
        'permissionKind': 'location',
        'bluetoothEnabled': true,
        'locationEnabled': false,
      });
      expect(status.locationPermission, isTrue);
      expect(status.bluetoothEnabled, isTrue);
      expect(status.locationEnabled, isFalse);
      expect(status.message, contains('Turn on location services'));
      expect(
        LedgerBluetoothAccessStatus.fromMap({
          'permission': 'settings',
          'platform': 'macOS',
        }).message,
        contains('System Settings'),
      );
    },
  );

  testWidgets(
    'duplicate clicks and resume events never duplicate permission request',
    (tester) async {
      final service = _Access()..permissionPending = Completer<bool>();
      await tester.pumpWidget(_harness(service));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow access'));
      await tester.pump();
      await tester.tap(find.text('Checking Bluetooth access…'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(service.requests, 1);
      service.permissionPending!.complete(false);
      await tester.pumpAndSettle();
      expect(service.requests, 1);
      expect(
        service.reads,
        3,
      ); // Initial, request result, one coalesced resume.
    },
  );

  test('permission gate never prompts or touches the Ledger', () async {
    final service = _Access();
    await expectLater(
      requireLedgerBluetoothAccess(service),
      throwsA(isA<LedgerMobileException>()),
    );
    expect(service.requests, 0);
    service.status = const LedgerBluetoothAccessStatus(
      LedgerBluetoothPermission.granted,
    );
    await requireLedgerBluetoothAccess(service);
    expect(service.requests, 0);
  });

  for (final failure in [
    LedgerMobileFailure.bluetoothOff,
    LedgerMobileFailure.locationDisabled,
  ]) {
    test('permission grant does not hide $failure', () async {
      final service = _Access()
        ..status = LedgerBluetoothAccessStatus(
          LedgerBluetoothPermission.granted,
          bluetoothEnabled: failure != LedgerMobileFailure.bluetoothOff,
          locationEnabled: failure != LedgerMobileFailure.locationDisabled,
        );
      await expectLater(
        requireLedgerBluetoothAccess(service),
        throwsA(
          isA<LedgerMobileException>().having(
            (e) => e.failure,
            'failure',
            failure,
          ),
        ),
      );
    });
  }

  testWidgets(
    'request is explicit, resume only reads and never retries signing',
    (tester) async {
      final service = _Access();
      await tester.pumpWidget(_harness(service));
      await tester.pumpAndSettle();
      expect(service.requests, 0);
      await tester.tap(find.text('Allow access'));
      await tester.pumpAndSettle();
      expect(service.requests, 1);
      service.status = const LedgerBluetoothAccessStatus(
        LedgerBluetoothPermission.granted,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Allow access'), findsNothing);
      expect(find.text('Ready to reconnect'), findsOneWidget);
      expect(service.requests, 1);
    },
  );

  testWidgets(
    'settings denial and launch failure keep manual recovery visible',
    (tester) async {
      final service = _Access()
        ..status = const LedgerBluetoothAccessStatus(
          LedgerBluetoothPermission.settings,
        )
        ..opensSettings = false;
      await tester.pumpWidget(_harness(service));
      await tester.pumpAndSettle();
      expect(find.text('Allow access'), findsNothing);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(service.settings, 1);
      expect(
        find.textContaining('Open your device settings manually'),
        findsOneWidget,
      );
      expect(find.text('Check again'), findsOneWidget);
    },
  );

  testWidgets('restricted access never offers repeated permission prompts', (
    tester,
  ) async {
    final service = _Access()
      ..status = const LedgerBluetoothAccessStatus(
        LedgerBluetoothPermission.restricted,
      );
    await tester.pumpWidget(_harness(service));
    await tester.pumpAndSettle();
    expect(find.text('Allow access'), findsNothing);
    expect(find.text(service.status.message), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('late read after cancellation cannot replace guidance', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = _Access()..pending = Completer();
    await tester.pumpWidget(_harness(service, container: container));
    container.read(ledgerDeviceRequestsProvider).cancel();
    service.pending!.complete(
      const LedgerBluetoothAccessStatus(LedgerBluetoothPermission.granted),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ready to reconnect'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late read after dismissal has no widget updates', (
    tester,
  ) async {
    final service = _Access()..pending = Completer();
    await tester.pumpWidget(_harness(service));
    await tester.pumpWidget(const SizedBox());
    service.pending!.complete(
      const LedgerBluetoothAccessStatus(LedgerBluetoothPermission.granted),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

const _account = AccountInfo(
  uuid: 'ledger',
  name: 'Ledger',
  order: 0,
  isHardware: true,
  hardwareSignerKind: HardwareSignerKind.ledger,
  ledgerDeviceId: 'flex',
  ledgerDeviceModel: 'Flex',
);

class _AccountsNotifier extends AccountNotifier {
  @override
  AccountState build() =>
      const AccountState(accounts: [_account], activeAccountUuid: 'ledger');
}
