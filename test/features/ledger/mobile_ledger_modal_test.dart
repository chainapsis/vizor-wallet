@Tags(['mobile'])
library;

import 'dart:async';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_selection.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile/mobile_ledger_sheet_content.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile_ledger_signing_surface.dart';
import 'ledger_pairing_recovery_test.dart' as fixture;

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Widget harness(Widget child, {double scale = 1}) => MaterialApp(
  home: AppTheme(
    data: AppThemeData.light,
    child: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Scaffold(body: Text('Review send')),
            child,
          ],
        ),
      ),
    ),
  ),
);

void main() {
  for (final failure in [
    LedgerMobileFailure.pairingInvalid,
    LedgerMobileFailure.disconnected,
    LedgerMobileFailure.pairingRejected,
  ]) {
    testWidgets('$failure retains the cause from selection to recovery UI', (
      tester,
    ) async {
      final ble = _FailingPairingBle(failure);
      final c = fixture.containerFor(
        ble,
        fixture.FakeAccounts(),
        platform: TargetPlatform.iOS,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: harness(
            MobileLedgerSigningSurface(
              canLeave: true,
              onBack: () {},
              child: LedgerSigningModal(
                accountUuid: 'a',
                phase: LedgerSigningModalPhase.awaitingDevice,
                failure: null,
                onCancel: () {},
                onFailureAction: null,
              ),
            ),
          ),
        ),
      );
      final operation = c
          .read(ledgerConnectionServiceProvider)
          .run(
            accountUuid: 'a',
            usb: () async => 'usb',
            bluetooth: (_) async => 'signed',
          )
          .then<Object>((value) => value, onError: (Object error) => error);
      await frames(tester);
      await tester.tap(find.text('Ledger Flex'));
      await frames(tester);
      final invalid = failure == LedgerMobileFailure.pairingInvalid;
      expect(
        find.text('Pair your Ledger again'),
        invalid ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Did you reset pairing?'),
        invalid ? findsNothing : findsOneWidget,
      );
      expect(
        find.textContaining('Open Settings > Bluetooth.'),
        invalid ? findsOneWidget : findsNothing,
      );
      expect(find.text('Open settings'), findsNothing);
      c.read(ledgerDeviceSelectionProvider)!.cancel();
      await operation;
      await frames(tester);
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform selecting saved device keeps the signer alive', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ble = fixture.FakeBle();
      final c = fixture.containerFor(
        ble,
        fixture.FakeAccounts(
          initial: fixture.account.copyWith(ledgerDeviceId: 'new'),
        ),
        platform: platform,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: harness(
            MobileLedgerSigningSurface(
              canLeave: true,
              onBack: () {},
              child: LedgerSigningModal(
                accountUuid: 'a',
                phase: LedgerSigningModalPhase.awaitingDevice,
                failure: null,
                onCancel: () {},
                onFailureAction: null,
              ),
            ),
          ),
        ),
      );
      final signed = Completer<String>();
      final result = c
          .read(ledgerConnectionServiceProvider)
          .run(
            accountUuid: 'a',
            usb: () async => 'usb',
            bluetooth: (_) => signed.future,
          );
      await frames(tester);
      expect(find.byType(AppModalCard), findsNothing);
      expect(find.byType(MobileModalCard), findsOneWidget);
      expect(find.text('Review send'), findsOneWidget);
      expect(find.text('Select your Ledger'), findsOneWidget);
      expect(find.text('USB'), findsNothing);
      expect(ble.calls, isNot(contains('connect')));
      await tester.tap(find.text('Ledger Flex'));
      await frames(tester);
      expect(c.read(ledgerDeviceSelectionProvider), isNull);
      expect(ble.calls, isNot(contains('cancel')));
      signed.complete('signed');
      expect(await result, 'signed');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'close settles pending selection before owner removes the sheet',
    (tester) async {
      final ble = fixture.FakeBle();
      final c = fixture.containerFor(
        ble,
        fixture.FakeAccounts(),
        platform: TargetPlatform.iOS,
      );
      addTearDown(c.dispose);
      var closes = 0;
      var signs = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: harness(
            MobileLedgerSigningSurface(
              canLeave: true,
              onBack: () {},
              child: LedgerSigningModal(
                accountUuid: 'a',
                phase: LedgerSigningModalPhase.awaitingDevice,
                failure: null,
                onCancel: () => closes++,
                onFailureAction: null,
              ),
            ),
          ),
        ),
      );
      final result = c
          .read(ledgerConnectionServiceProvider)
          .run(
            accountUuid: 'a',
            usb: () async => 'usb',
            bluetooth: (_) async {
              signs++;
              return 'signed';
            },
          )
          .then<Object>((value) => value, onError: (Object error) => error);
      await frames(tester);
      final request = c.read(ledgerDeviceSelectionProvider)!;
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Close',
        ),
      );
      await frames(tester);
      expect(request.completed, isTrue);
      expect(closes, 1);
      expect(signs, 0);
      expect(await result, isNot('signed'));
      expect(c.read(ledgerDeviceSelectionProvider), isNull);
    },
  );
  for (final action in ['backdrop', 'drag', 'back']) {
    for (final canLeave in [true, false]) {
      testWidgets('$action honors cancellation guard ($canLeave)', (
        tester,
      ) async {
        var calls = 0;
        await tester.pumpWidget(
          harness(
            MobileLedgerSigningSurface(
              canLeave: canLeave,
              onBack: () => calls++,
              child: MobileLedgerSheetContent(
                title: 'Confirm on your Ledger',
                onClose: null,
                children: const [
                  MobileLedgerMessage('Review and approve on your Ledger.'),
                ],
              ),
            ),
          ),
        );
        if (action == 'backdrop') {
          await tester.tapAt(const Offset(10, 10));
          await tester.tapAt(const Offset(10, 10));
        } else if (action == 'drag') {
          await tester.drag(
            find.text('Confirm on your Ledger'),
            const Offset(0, 100),
          );
        } else {
          await tester.binding.handlePopRoute();
          await tester.binding.handlePopRoute();
        }
        expect(calls, canLeave ? 1 : 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'failed cancellation re-enables dismissal without allowing duplicate calls',
    (tester) async {
      var calls = 0;
      Widget surface(bool canLeave) => harness(
        MobileLedgerSigningSurface(
          canLeave: canLeave,
          onBack: () => calls++,
          child: const MobileLedgerSheetContent(
            title: 'Confirm on your Ledger',
            onClose: null,
            children: [MobileLedgerMessage('Waiting for your Ledger.')],
          ),
        ),
      );

      await tester.pumpWidget(surface(true));
      await tester.binding.handlePopRoute();
      await tester.binding.handlePopRoute();
      expect(calls, 1);

      await tester.pumpWidget(surface(false));
      await tester.binding.handlePopRoute();
      expect(calls, 1);

      // Cleanup failed and the owner allows another cancellation attempt.
      await tester.pumpWidget(surface(true));
      await tester.binding.handlePopRoute();
      await tester.binding.handlePopRoute();
      expect(calls, 2);

      // A fast failure may coalesce the busy and recovery updates in one frame.
      await tester.pumpWidget(surface(true));
      await tester.binding.handlePopRoute();
      expect(calls, 3);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'small viewport and large text retain close and scrollable action',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var closes = 0;
      var retries = 0;
      await tester.pumpWidget(
        harness(
          MobileLedgerSigningSurface(
            canLeave: true,
            onBack: () => closes++,
            child: MobileLedgerSheetContent(
              title: 'Couldn’t connect to your Ledger',
              onClose: () => closes++,
              children: [
                const MobileLedgerMessage(
                  'Open Settings > Bluetooth. If your Ledger is listed, tap its info button and forget the device. Then come back and find your Ledger again.',
                ),
                MobileLedgerAction(
                  'Find my Ledger',
                  onPressed: () => retries++,
                ),
              ],
            ),
          ),
          scale: 1.8,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Find my Ledger'));
      await tester.tap(find.text('Find my Ledger'));
      expect(retries, 1);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Close',
        ),
      );
      expect(closes, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FailingPairingBle extends fixture.FakeBle {
  _FailingPairingBle(this.failure);
  final LedgerMobileFailure failure;
  @override
  Future<void> connect(LedgerBleDevice device) async {
    throw LedgerMobileException(failure, 'Native connection failure');
  }
}
