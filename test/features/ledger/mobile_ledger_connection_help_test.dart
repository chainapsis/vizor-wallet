@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/mobile_shield_scene.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_bluetooth_access.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_selection.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_access_recovery_modal.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile/mobile_ledger_connection_help.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile/mobile_ledger_help_navigation.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile/mobile_ledger_sheet_content.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile_ledger_signing_surface.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_ledger_device_sheet.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';

import 'ledger_pairing_recovery_test.dart' as fixture;

class _Ble extends fixture.FakeBle {
  bool opensSettings = true;
  Object? settingsError;
  Future<void>? stopGate;
  Object? stopError;
  @override
  Future<void> stopDiscovery() async {
    calls.add('stop');
    await stopGate;
    if (stopError case final error?) throw error;
  }

  @override
  Future<bool> openBluetoothPairingSettings() async {
    calls.add('settings');
    if (settingsError case final error?) throw error;
    return opensSettings;
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Widget _harness(Widget child, {double scale = 1}) => MaterialApp(
  home: AppTheme(
    data: AppThemeData.light,
    child: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Stack(fit: StackFit.expand, children: [child]),
      ),
    ),
  ),
);

Future<void> _press(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await _frames(tester);
}

void _chooseModel(WidgetTester tester, LedgerHelpModel model) {
  tester
      .widget<DropdownButton<LedgerHelpModel>>(
        find.byType(DropdownButton<LedgerHelpModel>),
      )
      .onChanged!(model);
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'inline shielding help navigates Back and retains Close at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final navigation = MobileLedgerHelpNavigation();
        var closes = 0;
        await tester.pumpWidget(
          _harness(
            MobileLedgerHelpScope(
              navigation: navigation,
              child: MobileShieldScene(
                phase: MobileShieldPhase.hardware,
                amount: '1',
                title: 'Shield with Ledger',
                animateHardware: true,
                onClose: () => closes++,
                onPrevious: () {
                  if (!navigation.previous()) closes++;
                },
                focusChild: LedgerInlinePresentation(
                  child: MobileLedgerConnectionHelp(
                    platform: TargetPlatform.iOS,
                    pairingInvalid: true,
                    initialModel: LedgerHelpModel.flex,
                    onBack: () {},
                    onClose: () => closes++,
                    onSearch: () {},
                  ),
                ),
              ),
            ),
            scale: scale,
          ),
        );
        await _frames(tester);
        await tester.pump(const Duration(seconds: 4));
        await _press(tester, 'Next: phone settings');
        await tester.binding.handlePopRoute();
        await _frames(tester);
        expect(find.text('Step 1 of 3 · On your Ledger'), findsOneWidget);
        expect(closes, 0);
        await _press(tester, 'Cancel shielding');
        expect(closes, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'onboarding help inside its operation surface consumes Back once',
    (tester) async {
      final ble = _Ble()..devices = [];
      var closes = 0;
      await tester.pumpWidget(
        _harness(
          MobileLedgerSigningSurface(
            canLeave: true,
            onBack: () => closes++,
            child: MobileLedgerDeviceSheet(
              service: ble,
              onSelected: (_) {},
              onClose: () => closes++,
            ),
          ),
        ),
      );
      await _frames(tester);
      await _press(tester, 'Connection help');
      await _press(tester, 'Reset Bluetooth pairing');
      _chooseModel(tester, LedgerHelpModel.flex);
      await _frames(tester);
      await _press(tester, 'Next: phone settings');
      await tester.binding.handlePopRoute();
      await _frames(tester);
      expect(find.text('Step 1 of 3 · On your Ledger'), findsOneWidget);
      expect(closes, 0);
    },
  );

  testWidgets('failed discovery cleanup can retry opening signing help', (
    tester,
  ) async {
    final ble = _Ble()..devices = [];
    final container = fixture.containerFor(
      ble,
      fixture.FakeAccounts(),
      platform: TargetPlatform.iOS,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _harness(
          LedgerAccessRecoveryModal(
            account: fixture.account,
            pairingRecovery: true,
            onRetry: () {},
            onClose: () {},
          ),
        ),
      ),
    );
    await _frames(tester);
    await _press(tester, 'Try again');
    ble.stopError = StateError('Native stop failed');
    await _press(tester, 'Connection help');
    expect(
      find.text(
        'Could not stop the search. Try opening connection help again.',
      ),
      findsOneWidget,
    );
    ble.stopError = null;
    await _press(tester, 'Connection help');
    expect(find.text('Find your Ledger'), findsOneWidget);
  });

  testWidgets(
    'returning from phone settings waits for search and rechecks Bluetooth',
    (tester) async {
      final ble = _Ble()..devices = [];
      final container = fixture.containerFor(
        ble,
        fixture.FakeAccounts(),
        platform: TargetPlatform.iOS,
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _harness(
            MobileLedgerDeviceSheet(
              service: ble,
              onSelected: (_) {},
              onClose: () {},
            ),
          ),
        ),
      );
      await _frames(tester);
      await _press(tester, 'Connection help');
      await _press(tester, 'Reset Bluetooth pairing');
      _chooseModel(tester, LedgerHelpModel.flex);
      await _frames(tester);
      await _press(tester, 'Next: phone settings');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      ble.access = const LedgerBluetoothAccessStatus(
        LedgerBluetoothPermission.granted,
        bluetoothEnabled: false,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _frames(tester);
      expect(find.text('Step 2 of 3 · On your phone'), findsOneWidget);
      expect(ble.calls.where((c) => c == 'scan'), hasLength(1));
      await _press(tester, 'Next: search in Vizor');
      await _press(tester, 'Search again');
      expect(find.text('Turn on Bluetooth'), findsOneWidget);
      expect(ble.calls.where((c) => c == 'scan'), hasLength(1));
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'onboarding empty result offers complete manual recovery ($platform)',
      (tester) async {
        final ble = _Ble()..devices = [];
        var closes = 0;
        await tester.pumpWidget(
          _harness(
            MobileLedgerDeviceSheet(
              service: ble,
              onSelected: (_) => fail('Help must not connect'),
              onClose: () => closes++,
            ),
          ),
        );
        await _frames(tester);
        expect(find.text('No Ledger devices found'), findsOneWidget);
        expect(find.text('Search again'), findsOneWidget);
        await _press(tester, 'Connection help');
        expect(find.text('Find your Ledger'), findsOneWidget);
        expect(find.textContaining('01AB'), findsNothing);
        expect(ble.calls.where((c) => c == 'scan'), hasLength(1));
        await _press(tester, 'Reset Bluetooth pairing');
        expect(
          tester
              .widget<AppButton>(
                find.widgetWithText(AppButton, 'Next: phone settings'),
              )
              .onPressed,
          isNull,
        );
        _chooseModel(tester, LedgerHelpModel.nanoX);
        await _frames(tester);
        expect(
          find.text('Settings > Security > Reset pairings'),
          findsOneWidget,
        );
        await _press(tester, 'Next: phone settings');
        expect(find.textContaining('01AB'), findsOneWidget);
        expect(find.textContaining('Device Name'), findsOneWidget);
        expect(find.textContaining('If Ledger is not listed'), findsOneWidget);
        expect(
          find.text('Open Bluetooth settings'),
          platform == TargetPlatform.android ? findsOneWidget : findsNothing,
        );
        await tester.binding.handlePopRoute();
        await _frames(tester);
        expect(find.text('Step 1 of 3 · On your Ledger'), findsOneWidget);
        expect(closes, 0);
        await _press(tester, 'Next: phone settings');
        await _press(tester, 'Next: search in Vizor');
        await _press(tester, 'Search again');
        expect(find.text('No Ledger devices found'), findsOneWidget);
        expect(find.text('Connection help'), findsOneWidget);
        expect(ble.calls.where((c) => c == 'scan'), hasLength(2));
        expect(ble.calls, isNot(contains('connect')));
        expect(closes, 0);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  testWidgets(
    'help opens only after discovery stops and ignores a dismissed preparation',
    (tester) async {
      final ble = _Ble()..devices = [];
      final gate = Completer<void>();
      var closes = 0;
      await tester.pumpWidget(
        _harness(
          MobileLedgerDeviceSheet(
            service: ble,
            onSelected: (_) {},
            onClose: () => closes++,
          ),
        ),
      );
      await _frames(tester);
      ble.stopGate = gate.future;
      await _press(tester, 'Connection help');
      expect(find.text('Find your Ledger'), findsNothing);
      final sheet = tester.widget<MobileLedgerDeviceSheet>(
        find.byType(MobileLedgerDeviceSheet),
      );
      // Use the displayed close action, which invalidates pending native results.
      expect(sheet.service, ble);
      await tester.tap(find.bySemanticsLabel('Close'));
      await _frames(tester);
      gate.complete();
      await _frames(tester);
      expect(closes, 1);
      expect(find.text('Find your Ledger'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final throws in [false, true]) {
    testWidgets(
      'Android settings failure retains phone step and has manual fallback (throws: $throws)',
      (tester) async {
        final ble = _Ble()
          ..devices = []
          ..opensSettings = false;
        if (throws) ble.settingsError = StateError('Unavailable');
        final container = fixture.containerFor(
          ble,
          fixture.FakeAccounts(),
          platform: TargetPlatform.android,
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _harness(
              MobileLedgerSigningSurface(
                canLeave: true,
                onBack: () {},
                child: LedgerAccessRecoveryModal(
                  account: fixture.account,
                  pairingRecovery: true,
                  pairingInvalid: true,
                  onRetry: () {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        );
        await _frames(tester);
        await _press(tester, 'Reset Bluetooth pairing');
        await _press(tester, 'Next: phone settings');
        await _press(tester, 'Open Bluetooth settings');
        expect(
          find.text(
            'Open Bluetooth settings manually to remove the old pairing.',
          ),
          findsOneWidget,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await _frames(tester);
        expect(find.text('Step 2 of 3 · On your phone'), findsOneWidget);
        expect(find.textContaining('Settings > Name'), findsOneWidget);
        expect(ble.calls, isNot(contains('scan')));
        await tester.binding.handlePopRoute();
        await _frames(tester);
        expect(find.text('Step 1 of 3 · On your Ledger'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'signing help keeps its selection request pending and Back never cancels it',
    (tester) async {
      final ble = _Ble()..devices = [];
      final accounts = fixture.FakeAccounts();
      final container = fixture.containerFor(
        ble,
        accounts,
        platform: TargetPlatform.iOS,
      );
      addTearDown(container.dispose);
      final request = LedgerDeviceSelectionRequest(
        accountUuid: 'a',
        check: () {},
        prepareDiscovery: () async {},
        stopDiscovery: ble.stopDiscovery,
        verify: (_, _, _) async =>
            throw StateError('Must not verify during help'),
      );
      unawaited(request.result.then<void>((_) {}, onError: (Object _) {}));
      var closes = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _harness(
            MobileLedgerSigningSurface(
              canLeave: true,
              onBack: () => closes++,
              child: LedgerAccessRecoveryModal(
                account: fixture.account,
                selectionRequest: request,
                onRetry: () {},
                onClose: () => closes++,
              ),
            ),
          ),
        ),
      );
      await _frames(tester);
      await _press(tester, 'Connection help');
      await _press(tester, 'Reset Bluetooth pairing');
      expect(request.completed, isFalse);
      expect(accounts.writes, 0);
      await tester.binding.handlePopRoute();
      await _frames(tester);
      expect(find.text('Find your Ledger'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _frames(tester);
      expect(find.text('No Ledger devices found'), findsOneWidget);
      expect(closes, 0);
      expect(request.completed, isFalse);
      await tester.pumpWidget(const SizedBox());
      await _frames(tester);
      expect(request.completed, isTrue);
    },
  );

  testWidgets('locking while in recovery prevents settings and new scans', (
    tester,
  ) async {
    final ble = _Ble()..devices = [];
    final container = fixture.containerFor(
      ble,
      fixture.FakeAccounts(),
      platform: TargetPlatform.android,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _harness(
          LedgerAccessRecoveryModal(
            account: fixture.account,
            pairingRecovery: true,
            pairingInvalid: true,
            onRetry: () {},
            onClose: () {},
          ),
        ),
      ),
    );
    await _frames(tester);
    await _press(tester, 'Reset Bluetooth pairing');
    await _press(tester, 'Next: phone settings');
    (container.read(appSecurityProvider.notifier) as fixture.FakeSecurity)
        .setUnlocked(false);
    await _frames(tester);
    await _press(tester, 'Open Bluetooth settings');
    expect(ble.calls, isNot(contains('settings')));
    expect(ble.calls, isNot(contains('scan')));
    expect(tester.takeException(), isNull);
  });

  for (final model in LedgerHelpModel.values) {
    testWidgets(
      'model-specific recovery is reachable at 320px and 2x text ($model)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _harness(
            MobileLedgerConnectionHelp(
              platform: TargetPlatform.iOS,
              pairingInvalid: true,
              initialModel: model,
              onBack: () {},
              onClose: () {},
              onSearch: () {},
            ),
            scale: 2,
          ),
        );
        await _frames(tester);
        await _press(tester, 'Next: phone settings');
        await tester.ensureVisible(find.text(model.nameHelp));
        await _frames(tester);
        expect(find.text(model.nameHelp), findsOneWidget);
        await _press(tester, 'Next: search in Vizor');
        expect(find.text('Search again'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
