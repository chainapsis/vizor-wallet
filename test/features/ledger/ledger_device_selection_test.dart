import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_selection.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'ledger_pairing_recovery_test.dart' as fixture;

void main() {
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    testWidgets(
      '$platform opens list without connecting and resumes after selection',
      (tester) async {
        final ble = fixture.FakeBle();
        final account = fixture.account.copyWith(
          ledgerConnectionPreference: LedgerConnectionPreference.bluetooth,
        );
        final accounts = fixture.FakeAccounts(initial: account);
        final c = fixture.containerFor(ble, accounts, platform: platform);
        addTearDown(c.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              home: AppTheme(
                data: AppThemeData.light,
                child: Center(
                  child: LedgerSigningModal(
                    phase: LedgerSigningModalPhase.awaitingDevice,
                    failure: null,
                    onCancel: () {},
                    onFailureAction: null,
                    accountUuid: 'a',
                  ),
                ),
              ),
            ),
          ),
        );
        var signs = 0;
        final result = c
            .read(ledgerConnectionServiceProvider)
            .run(
              accountUuid: 'a',
              usb: () async => 'usb',
              bluetooth: (_) async {
                signs++;
                return 'signed';
              },
            );
        await pumpFrames(tester);
        expect(find.text('Select your Ledger'), findsOneWidget);
        expect(find.text('Different from saved connection'), findsOneWidget);
        expect(
          find.text('USB'),
          platform == TargetPlatform.macOS ? findsOneWidget : findsNothing,
        );
        expect(ble.calls, contains('scan'));
        expect(ble.calls, isNot(contains('connect')));
        expect(signs, 0);
        await tester.tap(find.text('Ledger Flex'));
        await pumpFrames(tester);
        await tester.pump(const Duration(seconds: 1));
        await pumpFrames(tester);
        expect(await result, 'signed');
        expect(signs, 1);
        expect(ble.calls.where((e) => e == 'connect').length, 1);
        expect(find.text('Continue signing'), findsNothing);
        expect(c.read(ledgerDeviceSelectionProvider), isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'saved device shows connection copy and does not cancel the resumed signer',
    (tester) async {
      final readiness = Completer<void>();
      final ble = fixture.FakeBle()..readinessGate = readiness.future;
      final accounts = fixture.FakeAccounts(
        initial: fixture.account.copyWith(
          ledgerDeviceId: 'new',
          ledgerLastTransport: LedgerConnectionTransport.bluetooth,
        ),
      );
      final c = fixture.containerFor(
        ble,
        accounts,
        platform: TargetPlatform.iOS,
        export: () async => throw StateError('UFVK must not be requested'),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: Center(
                child: LedgerSigningModal(
                  phase: LedgerSigningModalPhase.awaitingDevice,
                  failure: null,
                  onCancel: () {},
                  onFailureAction: null,
                  accountUuid: 'a',
                ),
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
      await pumpFrames(tester);
      await tester.tap(find.text('Ledger Flex'));
      await pumpFrames(tester);
      expect(find.text('Connecting to your Ledger'), findsOneWidget);
      expect(
        find.textContaining('approve sharing the viewing key'),
        findsNothing,
      );
      expect(find.text('Checking account'), findsNothing);
      readiness.complete();
      await pumpFrames(tester);
      expect(c.read(ledgerDeviceSelectionProvider), isNull);
      expect(ble.calls, isNot(contains('cancel')));
      expect(accounts.writes, 0);
      signed.complete('signed');
      expect(await result, 'signed');
      expect(tester.takeException(), isNull);
    },
  );
  for (final cancel in ['close', 'dispose', 'lock', 'account']) {
    testWidgets('$cancel closes selection without signing', (tester) async {
      final ble = fixture.FakeBle();
      final accounts = fixture.FakeAccounts();
      final c = fixture.containerFor(
        ble,
        accounts,
        platform: TargetPlatform.iOS,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: Center(
                child: LedgerSigningModal(
                  phase: LedgerSigningModalPhase.awaitingDevice,
                  failure: null,
                  onCancel: () {},
                  onFailureAction: null,
                  accountUuid: 'a',
                ),
              ),
            ),
          ),
        ),
      );
      var signs = 0;
      final result = c
          .read(ledgerConnectionServiceProvider)
          .run(
            accountUuid: 'a',
            usb: () async => 'usb',
            bluetooth: (_) async {
              signs++;
              return 'signed';
            },
          );
      final expectation = expectLater(
        result,
        throwsA(isA<LedgerMobileException>()),
      );
      await pumpFrames(tester);
      switch (cancel) {
        case 'close':
          await tester.tap(find.bySemanticsLabel('Close'));
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
        case 'lock':
          (c.read(appSecurityProvider.notifier) as fixture.FakeSecurity)
              .setUnlocked(false);
        case 'account':
          accounts.changeActive('other');
      }
      await pumpFrames(tester);
      await expectation;
      expect(signs, 0);
      expect(ble.calls, isNot(contains('connect')));
      expect(c.read(ledgerDeviceSelectionProvider), isNull);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('mismatch stays in picker and a second selection can continue', (
    tester,
  ) async {
    final ble = fixture.FakeBle();
    final accounts = fixture.FakeAccounts();
    var match = false;
    final c = fixture.containerFor(
      ble,
      accounts,
      platform: TargetPlatform.iOS,
      export: () async => fixture.exported(match ? 'expected' : 'other'),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: Center(
              child: LedgerSigningModal(
                phase: LedgerSigningModalPhase.awaitingDevice,
                failure: null,
                onCancel: () {},
                onFailureAction: null,
                accountUuid: 'a',
              ),
            ),
          ),
        ),
      ),
    );
    var signs = 0;
    final result = c
        .read(ledgerConnectionServiceProvider)
        .run(
          accountUuid: 'a',
          usb: () async => 'usb',
          bluetooth: (_) async {
            signs++;
            return 'signed';
          },
        );
    await pumpFrames(tester);
    await tester.tap(find.text('Ledger Flex'));
    await pumpFrames(tester);
    expect(find.text('This Ledger doesn’t match'), findsOneWidget);
    expect(signs, 0);
    expect(accounts.writes, 0);
    match = true;
    await tester.tap(find.text('Choose another Ledger'));
    await pumpFrames(tester);
    await tester.tap(find.text('Ledger Flex'));
    await pumpFrames(tester);
    await tester.pump(const Duration(seconds: 1));
    await pumpFrames(tester);
    expect(await result, 'signed');
    expect(signs, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> pumpFrames(WidgetTester tester) async {
  // The signing screen intentionally keeps its progress animation running.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
