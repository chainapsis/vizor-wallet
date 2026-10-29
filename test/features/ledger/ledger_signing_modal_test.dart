import 'dart:io';

import 'package:zcash_wallet/src/features/ledger/services/ledger_device_selection.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/external_action_guard_provider.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_failure_guidance.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_procedure.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_modal_content.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('$platform signing uses USB despite saved Bluetooth metadata', (
      tester,
    ) async {
      final scope = LedgerConnectionScope();
      var retries = 0;
      for (final phase in [
        LedgerSigningModalPhase.preparing,
        LedgerSigningModalPhase.awaitingDevice,
        LedgerSigningModalPhase.failed,
      ]) {
        await tester.pumpWidget(
          _harness(
            platform: platform,
            phase: phase,
            stage: LedgerSigningStage.reviewing,
            account: _bluetoothAccount,
            connectionScope: scope,
            onFailureAction: () => retries++,
            failure: phase == LedgerSigningModalPhase.failed
                ? _usbConnectionFailure
                : null,
          ),
        );
        expect(find.text('My Ledger · USB'), findsOneWidget);
        expect(find.bySemanticsLabel('Change connection'), findsNothing);
        expect(find.byKey(const ValueKey('ledger_choose_usb')), findsNothing);
        expect(find.textContaining('Bluetooth'), findsNothing);
        expect(find.text('Auto'), findsNothing);
      }
      expect(find.text(_usbConnectionFailure.message), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
      expect(scope.transport, isNull);
    });
  }

  testWidgets('macOS signing identifies the current connection transport', (
    tester,
  ) async {
    final scope = LedgerConnectionScope();
    for (final transport in LedgerConnectionTransport.values) {
      scope.transport = transport;
      await tester.pumpWidget(
        _harness(
          phase: LedgerSigningModalPhase.awaitingDevice,
          stage: LedgerSigningStage.reviewing,
          account: _bluetoothAccount,
          connectionScope: scope,
        ),
      );
      expect(
        find.text(
          'My Ledger · ${transport == LedgerConnectionTransport.usb ? 'USB' : 'Bluetooth'}',
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets(
    'parks payment requests across signing phases and releases on exit',
    (tester) async {
      final visible = ValueNotifier(true);
      final phase = ValueNotifier(LedgerSigningModalPhase.awaitingDevice);
      addTearDown(visible.dispose);
      addTearDown(phase.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          ],
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (_, show, _) => show
                    ? ValueListenableBuilder<LedgerSigningModalPhase>(
                        valueListenable: phase,
                        builder: (_, value, _) => LedgerSigningModal(
                          phase: value,
                          failure: null,
                          onCancel: () {},
                          onFailureAction: null,
                        ),
                      )
                    : const SizedBox(),
              ),
            ),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      expect(container.read(externalActionGuardProvider).activeHoldCount, 1);
      phase.value = LedgerSigningModalPhase.saving;
      await tester.pump();
      expect(container.read(externalActionGuardProvider).activeHoldCount, 1);
      visible.value = false;
      await tester.pump();
      expect(container.read(externalActionGuardProvider).activeHoldCount, 0);
    },
  );

  testWidgets('separates the Ledger signer from the Zcash device app', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        phase: LedgerSigningModalPhase.awaitingDevice,
        stage: LedgerSigningStage.reviewing,
      ),
    );

    expect(find.text('Sign transaction'), findsOneWidget);
    expect(find.text('Ledger · USB'), findsOneWidget);
    expect(find.text('Review on Ledger'), findsOneWidget);
    expect(
      find.text('When prompted, check the amount and recipient on Ledger.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger_device_app_prompt_mainnet')),
      findsNothing,
    );
  });

  testWidgets(
    'preparation never claims approval, and live stages preserve the app prompt',
    (tester) async {
      const account = AccountInfo(
        uuid: 'ledger-1',
        name: 'Ledger',
        order: 0,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.ledger,
      );
      await tester.pumpWidget(
        _harness(
          phase: LedgerSigningModalPhase.awaitingDevice,
          account: account,
        ),
      );
      expect(find.text('Prepare transaction'), findsOneWidget);
      expect(find.text('Sign transaction'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LedgerSigningModal)),
      );
      final report = container
          .read(ledgerSigningProgressProvider.notifier)
          .begin(account.uuid);
      for (final phase in ['sending', 'reviewing', 'finishing']) {
        report(phase);
        await tester.pump();
        expect(find.text('Sign transaction'), findsOneWidget);
        expect(
          tester
              .widget<LedgerProcedure>(find.byType(LedgerProcedure))
              .currentStep,
          1,
        );
        if (phase == 'sending') {
          expect(
            find.text(
              'Ledger is preparing to sign. It may seem unresponsive for about 30 seconds.',
            ),
            findsOneWidget,
          );
        }
        expect(find.text('Open the Zcash app'), findsNothing);
      }
    },
  );

  testWidgets('keeps retry next to a failed signing status', (tester) async {
    var retryCount = 0;
    await tester.pumpWidget(
      _harness(
        phase: LedgerSigningModalPhase.failed,
        failure: const LedgerSigningFailurePresentation(
          title: 'Ledger signing failed',
          statusLabel: 'Action needed',
          message: 'Reconnect your Ledger and try again.',
          showDeviceAppPrompt: true,
          actionLabel: 'Try again',
        ),
        onFailureAction: () => retryCount++,
      ),
    );

    expect(find.text('Ledger signing failed'), findsOneWidget);
    expect(find.text('Action needed'), findsNothing);
    expect(find.text('Reconnect your Ledger and try again.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    expect(retryCount, 1);
  });

  testWidgets('asks for an app update when a memo was refused', (tester) async {
    var retryCount = 0;
    await tester.pumpWidget(
      _harness(
        phase: LedgerSigningModalPhase.failed,
        failure: ledgerMemoHashUpdateFailure,
        onFailureAction: () => retryCount++,
      ),
    );

    expect(find.text('Ledger app update required'), findsOneWidget);
    expect(find.text(ledgerMemoHashUnsupportedError), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retryCount, 1);
  });

  testWidgets('names a required app update the same way in every flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        phase: LedgerSigningModalPhase.failed,
        // Shielding and other overlays keep their own generic title.
        failure: const LedgerSigningFailurePresentation(
          requestFailure: LedgerRequestFailure.appUpdateRequired,
          title: 'Ledger signing failed',
          statusLabel: 'Action needed',
          message: ledgerNu7AppUpdateRequiredError,
          showDeviceAppPrompt: false,
          actionLabel: 'Try again',
        ),
      ),
    );

    expect(find.text(kLedgerAppUpdateRequiredTitle), findsOneWidget);
    expect(find.text('Ledger signing failed'), findsNothing);
    expect(find.text(ledgerNu7AppUpdateRequiredError), findsOneWidget);
  });

  testWidgets('explains automatic reconnect while opening Zcash', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        phase: LedgerSigningModalPhase.awaitingDevice,
        readiness: const LedgerAppReadinessState.inProgress(
          LedgerAppReadinessPhase.confirmOpening,
        ),
      ),
    );

    expect(find.text('Sign transaction'), findsOneWidget);
    expect(find.text('Confirm opening Zcash on Ledger.'), findsOneWidget);
    expect(find.text('Keep Zcash open.'), findsOneWidget);
  });

  testWidgets('does not replace the current failure with stale readiness', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        phase: LedgerSigningModalPhase.failed,
        failure: const LedgerSigningFailurePresentation(
          title: 'Ledger signing failed',
          statusLabel: 'Action needed',
          message: 'Open the Zcash app, then try again.',
          showDeviceAppPrompt: true,
          actionLabel: 'Try again',
        ),
        readiness: const LedgerAppReadinessState.failed(
          failure: LedgerAppReadinessFailure.unsupportedVersion,
          message: 'Update the Ledger Zcash app to version 3.9.3 or newer.',
        ),
      ),
    );

    expect(find.text('Ledger signing failed'), findsOneWidget);
    expect(find.text('Open the Zcash app, then try again.'), findsOneWidget);
    expect(
      find.text('Update the Ledger Zcash app to version 3.9.3 or newer.'),
      findsNothing,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('shows checkpoint saving without a cancel action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(phase: LedgerSigningModalPhase.saving, onCancel: null),
    );

    expect(find.text('Finish transaction'), findsOneWidget);
    expect(find.text('Saving the signed transaction.'), findsOneWidget);
    expect(find.text('Finishing'), findsNothing);
    expect(find.text('Waiting'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Open the Zcash app'), findsNothing);
  });

  testWidgets('supports a checkpoint-only recovery action', (tester) async {
    var retrySavingCount = 0;
    await tester.pumpWidget(
      _harness(
        phase: LedgerSigningModalPhase.failed,
        failure: const LedgerSigningFailurePresentation(
          title: 'Could not save signed transaction',
          statusLabel: 'Signature preserved',
          message: 'Retry saving without approving another transaction.',
          showDeviceAppPrompt: false,
          actionLabel: 'Retry saving',
        ),
        onCancel: null,
        onFailureAction: () => retrySavingCount++,
      ),
    );

    expect(find.text('Retry saving'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Open the Zcash app'), findsNothing);

    await tester.tap(find.text('Retry saving'));
    expect(retrySavingCount, 1);
  });

  testWidgets(
    'Ledger modal takes keyboard focus and returns it to its caller',
    (tester) async {
      final opener = FocusNode();
      addTearDown(opener.dispose);
      var visible = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: StatefulBuilder(
              builder: (context, update) => Stack(
                children: [
                  Center(
                    child: TextButton(
                      focusNode: opener,
                      onPressed: () => update(() => visible = true),
                      child: const Text('Open signing'),
                    ),
                  ),
                  if (visible)
                    Center(
                      child: LedgerModalContent(
                        title: 'Sign transaction',
                        footer: AppButton(
                          onPressed: () => update(() => visible = false),
                          child: const Text('Cancel'),
                        ),
                        child: const Text('Keep Ledger connected.'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      opener.requestFocus();
      await tester.pump();
      await tester.tap(find.text('Open signing'));
      await tester.pump();
      expect(opener.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus!;
      expect(
        focus.debugLabel == 'Ledger modal' ||
            focus.ancestors.any((node) => node.debugLabel == 'Ledger modal'),
        isTrue,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(opener.hasFocus, isTrue);
    },
  );

  testWidgets('Ledger modal keeps actions reachable at 200 percent text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 600),
              textScaler: TextScaler.linear(2),
            ),
            child: Center(
              child: SizedBox(
                height: 500,
                child: LedgerModalContent(
                  title: 'Connect Ledger',
                  footer: AppButton(
                    onPressed: () {},
                    child: const Text('Cancel'),
                  ),
                  child: Column(
                    children: List.generate(
                      12,
                      (i) => Text(
                        'Instruction $i: keep Ledger connected and review the request.',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomRight(find.text('Cancel')).dy,
      lessThanOrEqualTo(600),
    );
    final cancelPosition = tester.getCenter(find.text('Cancel'));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pump();
    expect(tester.getCenter(find.text('Cancel')), cancelPosition);
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('$platform exposes connection choice only when supported', (
      tester,
    ) async {
      final scope = LedgerConnectionScope()
        ..transport = LedgerConnectionTransport.usb;
      var retries = 0;
      await tester.pumpWidget(
        _harness(
          phase: LedgerSigningModalPhase.failed,
          failure: const LedgerSigningFailurePresentation(
            title: 'Ledger signing failed',
            statusLabel: 'Action needed',
            message: 'Reconnect your Ledger and try again.',
            showDeviceAppPrompt: true,
            actionLabel: 'Try again',
          ),
          connectionScope: scope,
          platform: platform,
          onFailureAction: () => retries++,
        ),
      );
      expect(find.text('Auto'), findsNothing);
      final back = find.bySemanticsLabel('Change connection');
      expect(
        back,
        platform == TargetPlatform.macOS ? findsOneWidget : findsNothing,
      );
      if (platform == TargetPlatform.macOS) {
        await tester.tap(back);
        expect(scope.transport, isNull);
        expect(retries, 1);
      }
    });
  }

  testWidgets('captures USB-only signing and connection recovery', (
    tester,
  ) async {
    const output = String.fromEnvironment('LEDGER_SIGNING_USB_CAPTURE_DIR');
    if (output.isEmpty) return;
    Directory(output).createSync(recursive: true);
    await loadFigmaCompareFonts();
    final shadowsWereDisabled = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = shadowsWereDisabled);
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      for (final theme in [AppThemeData.light, AppThemeData.dark]) {
        for (final failed in [false, true]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          const boundary = ValueKey('ledger_signing_usb_capture');
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: _harness(
                platform: platform,
                theme: theme,
                phase: failed
                    ? LedgerSigningModalPhase.failed
                    : LedgerSigningModalPhase.awaitingDevice,
                stage: LedgerSigningStage.reviewing,
                account: _bluetoothAccount,
                connectionScope: LedgerConnectionScope(),
                failure: failed ? _usbConnectionFailure : null,
                onFailureAction: _noop,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('My Ledger · USB'), findsOneWidget);
          expect(find.textContaining('Bluetooth'), findsNothing);
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(boundary),
            matchesGoldenFile(
              File(
                '$output/${platform.name}-${failed ? 'failed' : 'reviewing'}-${theme == AppThemeData.dark ? 'dark' : 'light'}.png',
              ).uri,
            ),
          );
        }
      }
    }
    debugDisableShadows = shadowsWereDisabled;
  }, tags: ['figma-capture']);
}

Widget _harness({
  required LedgerSigningModalPhase phase,
  LedgerSigningFailurePresentation? failure,
  LedgerSigningStage? stage,
  LedgerAppReadinessState readiness = const LedgerAppReadinessState.idle(),
  VoidCallback? onFailureAction,
  VoidCallback? onCancel = _noop,
  AccountInfo? account,
  LedgerConnectionScope? connectionScope,
  TargetPlatform platform = TargetPlatform.macOS,
  AppThemeData theme = AppThemeData.light,
}) {
  return ProviderScope(
    key: ValueKey(readiness.phase),
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      ledgerAppReadinessStateProvider.overrideWith(
        () => _FakeReadinessController(readiness),
      ),
      ledgerTargetPlatformProvider.overrideWithValue(platform),
      if (account != null)
        accountProvider.overrideWith(() => _StaticAccountNotifier(account)),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) => AppTheme(
          data: theme,
          child: Material(
            color: theme.colors.background.window,
            child: Center(
              child: LedgerSigningModal(
                phase: phase,
                connectionScope: connectionScope,
                signingStage: stage,
                failure: failure,
                onCancel: onCancel,
                onFailureAction: onFailureAction,
                accountUuid: account?.uuid,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void _noop() {}

const _bluetoothAccount = AccountInfo(
  uuid: 'ledger-1',
  name: 'Ledger',
  order: 0,
  isHardware: true,
  hardwareSignerKind: HardwareSignerKind.ledger,
  ledgerDeviceId: 'saved',
  ledgerDeviceName: 'My Ledger',
  ledgerDeviceModel: 'Nano X',
  ledgerLastTransport: LedgerConnectionTransport.bluetooth,
);

const _usbConnectionFailure = LedgerSigningFailurePresentation(
  title: 'Ledger signing failed',
  statusLabel: 'Action needed',
  message: 'Connect and unlock your Ledger with USB, then try again.',
  showDeviceAppPrompt: false,
  actionLabel: 'Try again',
);

class _FakeReadinessController extends LedgerAppReadinessController {
  _FakeReadinessController(this.initialState);

  final LedgerAppReadinessState initialState;

  @override
  LedgerAppReadinessState build() => initialState;
}

class _StaticAccountNotifier extends AccountNotifier {
  _StaticAccountNotifier(this.account);

  final AccountInfo account;

  @override
  AccountState build() =>
      AccountState(accounts: [account], activeAccountUuid: account.uuid);
}
