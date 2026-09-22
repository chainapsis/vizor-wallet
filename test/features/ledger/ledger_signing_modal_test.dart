import 'package:zcash_wallet/src/features/ledger/services/ledger_device_selection.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_busy_surface_provider.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('$platform failure does not offer a transport choice', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          platform: platform,
          phase: LedgerSigningModalPhase.failed,
          account: const AccountInfo(
            uuid: 'ledger-1',
            name: 'Ledger',
            order: 0,
            isHardware: true,
            hardwareSignerKind: HardwareSignerKind.ledger,
            ledgerDeviceId: 'saved',
            ledgerDeviceModel: 'Nano X',
          ),
          failure: const LedgerSigningFailurePresentation(
            title: 'Ledger signing failed',
            statusLabel: 'Action needed',
            message: 'Reconnect your Ledger and try again.',
            showDeviceAppPrompt: true,
            actionLabel: 'Try again',
          ),
        ),
      );
      expect(find.bySemanticsLabel('Change connection'), findsNothing);
      expect(find.text('Bluetooth'), findsNothing);
      expect(find.text('Auto'), findsNothing);
    });
  }

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
      expect(container.read(paymentUriBusySurfaceProvider), 1);
      phase.value = LedgerSigningModalPhase.saving;
      await tester.pump();
      expect(container.read(paymentUriBusySurfaceProvider), 1);
      visible.value = false;
      await tester.pump();
      expect(container.read(paymentUriBusySurfaceProvider), 0);
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

    expect(find.text('Check your Ledger'), findsOneWidget);
    expect(find.text('Zcash · Ledger'), findsOneWidget);
    expect(find.text('Open the Zcash app'), findsOneWidget);
    expect(find.text('Review on device'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ledger_device_app_prompt_mainnet')),
      findsOneWidget,
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
      expect(find.text('Preparing transaction'), findsOneWidget);
      expect(find.text('Check your Ledger'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LedgerSigningModal)),
      );
      final report = container
          .read(ledgerSigningProgressProvider.notifier)
          .begin(account.uuid);
      for (final phase in ['sending', 'reviewing', 'finishing']) {
        report(phase);
        await tester.pump();
        final expected = switch (phase) {
          'sending' => 'Processing with Ledger',
          'reviewing' => 'Check your Ledger',
          _ => 'Finishing transaction',
        };
        expect(find.text(expected), findsOneWidget);
        if (phase == 'sending') {
          expect(find.text('Preparing to sign'), findsOneWidget);
          expect(find.text('Please wait'), findsNothing);
        }
        expect(find.text('Open the Zcash app'), findsOneWidget);
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
    expect(find.text('Action needed'), findsOneWidget);
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

    expect(find.text('Confirm opening Zcash'), findsOneWidget);
    expect(find.text('Opening Zcash'), findsOneWidget);
    expect(
      find.text(
        'Confirm the request on your Ledger. Vizor will reconnect automatically.',
      ),
      findsOneWidget,
    );
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

    expect(find.text('Finishing transaction'), findsOneWidget);
    expect(find.text('Please wait'), findsOneWidget);
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
      home: Builder(
        builder: (context) => AppTheme(
          data: AppThemeData.light,
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
  );
}

void _noop() {}

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
