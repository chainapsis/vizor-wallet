import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

void main() {
  testWidgets('separates the Ledger signer from the Zcash device app', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(phase: LedgerSigningModalPhase.awaitingDevice),
    );

    expect(find.text('Review on your Ledger'), findsOneWidget);
    expect(find.text('Zcash · Ledger'), findsOneWidget);
    expect(find.text('Open the Zcash app'), findsOneWidget);
    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ledger_device_app_prompt_mainnet')),
      findsOneWidget,
    );
  });

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

  testWidgets('surfaces a typed readiness failure beside retry', (
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
          message: 'Update the Ledger Zcash app to version 3.9.2 or newer.',
        ),
      ),
    );

    expect(find.text('Ledger needs attention'), findsOneWidget);
    expect(
      find.text('Update the Ledger Zcash app to version 3.9.2 or newer.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('shows checkpoint saving without a cancel action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(phase: LedgerSigningModalPhase.saving, onCancel: null),
    );

    expect(find.text('Saving signed transaction'), findsOneWidget);
    expect(find.text('Securing transaction'), findsOneWidget);
    expect(find.text('Saving'), findsOneWidget);
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

  testWidgets('offers a compact transport switch after a signing failure', (
    tester,
  ) async {
    const account = AccountInfo(
      uuid: 'ledger-1',
      name: 'Ledger',
      order: 0,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
      ledgerDeviceId: 'nano-x',
      ledgerDeviceModel: 'Nano X',
    );
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
        account: account,
      ),
    );

    expect(
      find.byKey(const ValueKey('ledger_failure_connection_picker')),
      findsOneWidget,
    );
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('USB'), findsOneWidget);
    expect(find.text('Bluetooth'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('ledger_connection_bluetooth')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('does not offer Bluetooth before the account verifies a device', (
    tester,
  ) async {
    const account = AccountInfo(
      uuid: 'ledger-1',
      name: 'Ledger',
      order: 0,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
      ledgerDeviceModel: 'Nano S Plus',
    );
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
        account: account,
      ),
    );

    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('ledger_connection_bluetooth')),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Set up Bluetooth'), findsOneWidget);
  });
}

Widget _harness({
  required LedgerSigningModalPhase phase,
  LedgerSigningFailurePresentation? failure,
  LedgerAppReadinessState readiness = const LedgerAppReadinessState.idle(),
  VoidCallback? onFailureAction,
  VoidCallback? onCancel = _noop,
  AccountInfo? account,
}) {
  return ProviderScope(
    key: ValueKey(readiness.phase),
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      ledgerAppReadinessStateProvider.overrideWith(
        () => _FakeReadinessController(readiness),
      ),
      ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
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
