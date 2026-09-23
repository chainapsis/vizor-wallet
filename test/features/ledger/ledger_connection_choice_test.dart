import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_selection.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_access_recovery_modal.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'ledger_pairing_recovery_test.dart' as fixture;
import 'ledger_device_selection_test.dart' show pumpFrames;

void main() {
  testWidgets(
    'USB failure can retry or return to choice without starting Bluetooth',
    (tester) async {
      var usbCalls = 0;
      final ble = fixture.FakeBle();
      final c = fixture.containerFor(ble, fixture.FakeAccounts());
      addTearDown(c.dispose);
      final request = LedgerDeviceSelectionRequest(
        accountUuid: 'a',
        check: () {},
        canChooseTransport: true,
        prepareDiscovery: () async => throw StateError('Unexpected Bluetooth'),
        verify: (_, _, _) async => false,
        prepareUsb: () async {
          usbCalls++;
          if (usbCalls == 1) throw StateError('No USB device');
        },
      );
      final result = request.result;
      await tester.pumpWidget(_modal(c, request));
      expect(usbCalls, 0);
      expect(ble.calls, isEmpty);
      await tester.tap(find.text('USB'));
      await pumpFrames(tester);
      expect(find.text('Couldn’t connect to your Ledger'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Change connection'));
      await pumpFrames(tester);
      expect(find.text('How would you like to connect?'), findsOneWidget);
      expect(usbCalls, 1);
      expect(ble.calls, isEmpty);
      await tester.tap(find.text('USB'));
      await pumpFrames(tester);
      expect((await result).device, isNull);
      expect(usbCalls, 2);
    },
  );

  testWidgets('returning from Bluetooth stops discovery before enabling USB', (
    tester,
  ) async {
    final ble = fixture.FakeBle();
    final c = fixture.containerFor(ble, fixture.FakeAccounts());
    addTearDown(c.dispose);
    final stop = Completer<void>();
    var stops = 0;
    var usbCalls = 0;
    LedgerConnectionTransport? chosen;
    final request = LedgerDeviceSelectionRequest(
      accountUuid: 'a',
      check: () {},
      canChooseTransport: true,
      onTransportChanged: (value) => chosen = value,
      prepareDiscovery: () async {},
      verify: (_, _, _) async => false,
      stopDiscovery: () async {
        stops++;
        await ble.stopDiscovery();
        await stop.future;
      },
      prepareUsb: () async {
        usbCalls++;
      },
    );
    final result = request.result;
    await tester.pumpWidget(_modal(c, request));
    await tester.tap(find.text('Bluetooth'));
    await pumpFrames(tester);
    expect(chosen, LedgerConnectionTransport.bluetooth);
    expect(find.text('Select your Ledger'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Change connection'));
    await pumpFrames(tester);
    expect(stops, 1);
    expect(find.text('USB'), findsNothing);
    expect(usbCalls, 0);
    stop.complete();
    await pumpFrames(tester);
    expect(chosen, isNull);
    expect(ble.calls.where((call) => call == 'stop'), hasLength(1));
    expect(find.text('USB'), findsOneWidget);
    await tester.tap(find.text('USB'));
    await pumpFrames(tester);
    await result;
    expect(usbCalls, 1);
  });

  test(
    'cancelling USB readiness drains its work and cannot select a device',
    () async {
      final ready = Completer<void>();
      final request = LedgerDeviceSelectionRequest(
        accountUuid: 'a',
        check: () {},
        canChooseTransport: true,
        prepareDiscovery: () async {},
        verify: (_, _, _) async => false,
        prepareUsb: () => ready.future,
      );
      var drained = false;
      final result = expectLater(
        request.result.whenComplete(() => drained = true),
        throwsA(isA<LedgerMobileException>()),
      );
      final selecting = expectLater(
        request.selectUsb(),
        throwsA(isA<LedgerMobileException>()),
      );
      request.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(drained, false);
      ready.complete();
      await selecting;
      await result;
      expect(drained, true);
    },
  );
}

Widget _modal(ProviderContainer c, LedgerDeviceSelectionRequest request) =>
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Center(
            child: LedgerAccessRecoveryModal(
              account: fixture.account,
              selectionRequest: request,
              onRetry: () {},
              onClose: request.cancel,
            ),
          ),
        ),
      ),
    );
