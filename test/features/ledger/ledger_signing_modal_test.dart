import 'dart:async';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_recovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile_ledger_signing_surface.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_pairing_code_provider.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

void main() {
  testWidgets(
    'page layout keeps actions at the bottom while guidance scrolls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Rect? actions;
      for (final phase in [
        LedgerSigningModalPhase.awaitingDevice,
        LedgerSigningModalPhase.reconnecting,
        LedgerSigningModalPhase.readyToRetry,
      ]) {
        await tester.pumpWidget(
          _harness(
            phase: phase,
            pageLayout: true,
            readiness: const LedgerAppReadinessState.ready('3.9.3'),
          ),
        );
        expect(find.byType(AppModalCard), findsNothing);
        final guidanceAnnouncement = find.ancestor(
          of: find.byKey(const ValueKey('ledger_action_guidance')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        );
        expect(guidanceAnnouncement, findsOneWidget);
        // The header keeps the Ledger mark at the leading edge with the
        // headline and account name beside it.
        final accountRow = find.byKey(const ValueKey('ledger_signing_account'));
        final iconBounds = tester.getRect(
          find.descendant(of: accountRow, matching: find.byType(AppIcon)),
        );
        final nameBounds = tester.getRect(
          find.descendant(of: accountRow, matching: find.text('Ledger')),
        );
        expect(iconBounds.left, lessThan(nameBounds.left));
        expect(
          iconBounds.center.dy,
          closeTo(
            accountRow.evaluate().isEmpty
                ? 0
                : tester.getRect(accountRow).center.dy,
            1,
          ),
        );
        final bounds = tester.getRect(
          find.byKey(const ValueKey('ledger_signing_actions')),
        );
        if (actions != null) expect(bounds, actions);
        actions = bounds;
        expect(bounds.bottom, lessThanOrEqualTo(568));
        if (phase == LedgerSigningModalPhase.awaitingDevice) {
          await tester.ensureVisible(find.text('Waiting for your approval'));
          expect(
            find.text('Waiting for your approval').hitTestable(),
            findsOneWidget,
          );
        } else {
          expect(
            find.text('Waiting for your approval').hitTestable(),
            findsNothing,
          );
        }
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -150),
        );
        await tester.pump();
        expect(
          tester.getRect(find.byKey(const ValueKey('ledger_signing_actions'))),
          bounds,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'device guidance keeps actions anchored through app opening and recovery',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Rect? cancelBounds;
      var retries = 0;
      for (final (phase, readiness) in [
        (
          LedgerSigningModalPhase.preparing,
          const LedgerAppReadinessState.idle(),
        ),
        (
          LedgerSigningModalPhase.awaitingDevice,
          const LedgerAppReadinessState.inProgress(
            LedgerAppReadinessPhase.confirmOpening,
          ),
        ),
        (
          LedgerSigningModalPhase.awaitingDevice,
          const LedgerAppReadinessState.ready('3.9.3'),
        ),
        (
          LedgerSigningModalPhase.reconnecting,
          const LedgerAppReadinessState.idle(),
        ),
        (
          LedgerSigningModalPhase.readyToRetry,
          const LedgerAppReadinessState.idle(),
        ),
      ]) {
        await tester.pumpWidget(
          _harness(
            phase: phase,
            readiness: readiness,
            onFailureAction: () => retries++,
          ),
        );
        final bounds = tester.getRect(find.text('Cancel'));
        if (cancelBounds != null) expect(bounds, cancelBounds);
        cancelBounds = bounds;
        expect(tester.takeException(), isNull);
      }
      expect(retries, 0);
      // Reconnected: the app line reports the connection and the status card
      // waits for the retry.
      expect(
        find.byKey(const ValueKey('ledger_signing_step_app_done')),
        findsOneWidget,
      );
      expect(find.text('Connected'), findsWidgets);
      expect(find.text('Ready when you are'), findsOneWidget);
      final retryBounds = tester.getRect(find.text('Try again'));
      expect(retryBounds.center.dx, cancelBounds!.center.dx);
      expect(retryBounds.bottom, lessThan(cancelBounds.top));
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    },
  );

  testWidgets('preparation transitions keep guidance and cancel in place', (
    tester,
  ) async {
    Rect? guidance;
    Rect? cancel;
    for (final phase in [
      LedgerSigningModalPhase.preparing,
      LedgerSigningModalPhase.connecting,
      LedgerSigningModalPhase.coolingDown,
      LedgerSigningModalPhase.awaitingDevice,
    ]) {
      await tester.pumpWidget(_harness(phase: phase));
      expect(find.text('Getting ready'), findsOneWidget);
      expect(find.text('Waiting'), findsNothing);
      final nextGuidance = tester.getRect(
        find.byKey(const ValueKey('ledger_action_guidance')),
      );
      final nextCancel = tester.getRect(find.text('Cancel'));
      if (guidance != null) expect(nextGuidance, guidance);
      if (cancel != null) expect(nextCancel, cancel);
      guidance = nextGuidance;
      cancel = nextCancel;
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('equivalent parent rebuild preserves pending recovery', (
    tester,
  ) async {
    final completed = Completer<void>();
    var reconnects = 0;
    Future<void> reconnect(String _) {
      reconnects++;
      return completed.future;
    }

    Widget build() => _harness(
      phase: LedgerSigningModalPhase.failed,
      account: const AccountInfo(
        uuid: 'ledger-1',
        name: 'Ledger',
        order: 0,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.ledger,
      ),
      // Intentionally allocate a new presentation on each parent rebuild.
      failure: LedgerSigningFailurePresentation(
        title: 'Failed',
        statusLabel: 'Interrupted',
        message: 'Disconnected',
        actionLabel: 'Try again',
        requiresReconnect: true,
      ),
      reconnect: reconnect,
    );

    await tester.pumpWidget(build());
    await tester.ensureVisible(find.text('Reconnect'));
    await tester.tap(find.text('Reconnect'));
    await tester.pump();
    await tester.pumpWidget(build());
    expect(find.text('Reconnecting your Ledger'), findsOneWidget);
    expect(find.text('Reconnect'), findsNothing);
    completed.complete();
    await tester.pump();
    expect(find.text('Ready when you are'), findsOneWidget);
    expect(reconnects, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reconnect stays in modal and never triggers signing automatically',
    (tester) async {
      final completed = Completer<void>();
      var reconnects = 0;
      var signs = 0;
      await tester.pumpWidget(
        _harness(
          phase: LedgerSigningModalPhase.failed,
          account: const AccountInfo(
            uuid: 'ledger-1',
            name: 'Ledger',
            order: 0,
            isHardware: true,
            hardwareSignerKind: HardwareSignerKind.ledger,
          ),
          failure: const LedgerSigningFailurePresentation(
            title: 'Failed',
            statusLabel: 'Interrupted',
            message: 'Disconnected',
            actionLabel: 'Try again',
            requiresReconnect: true,
          ),
          reconnect: (_) {
            reconnects++;
            return completed.future;
          },
          onFailureAction: () => signs++,
        ),
      );
      await tester.ensureVisible(find.text('Reconnect'));
      await tester.tap(find.text('Reconnect'));
      await tester.pump();
      expect(find.text('Reconnecting your Ledger'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(signs, 0);
      completed.complete();
      await tester.pump();
      expect(find.text('Ready when you are'), findsOneWidget);
      expect(signs, 0);
      await tester.tap(find.text('Try again'));
      expect(signs, 1);
      expect(reconnects, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed reconnect keeps retry separate from signing', (
    tester,
  ) async {
    var signs = 0;
    await tester.pumpWidget(
      _harness(
        phase: LedgerSigningModalPhase.failed,
        account: const AccountInfo(
          uuid: 'ledger-1',
          name: 'Ledger',
          order: 0,
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
        ),
        failure: const LedgerSigningFailurePresentation(
          title: 'Failed',
          statusLabel: 'Interrupted',
          message: 'Disconnected',
          actionLabel: 'Try again',
          requiresReconnect: true,
        ),
        reconnect: (_) async => throw StateError('Connection is still closing'),
        onFailureAction: () => signs++,
      ),
    );
    await tester.ensureVisible(find.text('Reconnect'));
    await tester.tap(find.text('Reconnect'));
    await tester.pump();
    expect(find.textContaining('Connection is still closing'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(signs, 0);
  });
  testWidgets('separates the Ledger signer from the Zcash device app', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(phase: LedgerSigningModalPhase.awaitingDevice),
    );

    expect(find.text('Getting ready'), findsOneWidget);
    expect(find.text('Zcash · Ledger'), findsNothing);
    expect(find.text('Open the Zcash app'), findsNothing);
    expect(find.text('Waiting for approval'), findsNothing);
    expect(find.text('Waiting'), findsNothing);
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

    expect(find.text('Open the Zcash app'), findsOneWidget);
    expect(
      find.text('Confirm the app opening request on your Ledger.'),
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
          actionLabel: 'Try again',
        ),
        readiness: const LedgerAppReadinessState.failed(
          failure: LedgerAppReadinessFailure.unsupportedVersion,
          message: 'Update the Ledger Zcash app to version 3.9.3 or newer.',
        ),
      ),
    );

    expect(find.text('Ledger needs attention'), findsOneWidget);
    expect(
      find.text('Update the Ledger Zcash app to version 3.9.3 or newer.'),
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
    expect(find.text('Saving'), findsNothing);
    expect(find.text('Cancel').hitTestable(), findsNothing);
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
          actionLabel: 'Retry saving',
        ),
        onCancel: null,
        onFailureAction: () => retrySavingCount++,
      ),
    );

    expect(find.text('Retry saving'), findsOneWidget);
    expect(find.text('Cancel').hitTestable(), findsNothing);
    expect(find.text('Open the Zcash app'), findsNothing);

    await tester.tap(find.text('Retry saving'));
    expect(retrySavingCount, 1);
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      '$platform offers a compact transport switch after a signing failure',
      (tester) async {
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
            platform: platform,
            failure: const LedgerSigningFailurePresentation(
              title: 'Ledger signing failed',
              statusLabel: 'Action needed',
              message: 'Reconnect your Ledger and try again.',
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
      },
    );
  }

  testWidgets('asks to compare the Linux pairing code before pairing', (
    tester,
  ) async {
    // A pairing can surface during any connect the request makes.
    for (final phase in [
      LedgerSigningModalPhase.connecting,
      LedgerSigningModalPhase.awaitingDevice,
      LedgerSigningModalPhase.reconnecting,
    ]) {
      final answers = <bool>[];
      await tester.pumpWidget(
        _harness(
          platform: TargetPlatform.linux,
          phase: phase,
          pairingCode: '123456',
          pairingAnswers: answers,
        ),
      );
      await tester.pump();
      expect(find.text('Confirm pairing on your Ledger'), findsOneWidget);
      expect(find.text('123456'), findsOneWidget);
      expect(
        find.text('Pair only if your Ledger shows the same code.'),
        findsOneWidget,
      );
      expect(find.text('Codes differ'), findsOneWidget);
      await tester.ensureVisible(find.text('Codes match'));
      await tester.tap(find.text('Codes match'));
      await tester.pump();
      expect(answers, [true]);
      expect(find.text('Approve pairing on your Ledger'), findsOneWidget);
      expect(find.text('Codes match'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    final rejected = <bool>[];
    await tester.pumpWidget(
      _harness(
        platform: TargetPlatform.linux,
        phase: LedgerSigningModalPhase.awaitingDevice,
        pairingCode: '654321',
        pairingAnswers: rejected,
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Codes differ'));
    await tester.tap(find.text('Codes differ'));
    await tester.pump();
    expect(rejected, [false]);
    await tester.pumpWidget(const SizedBox.shrink());
    // Terminal phases never show a prompt.
    await tester.pumpWidget(
      _harness(
        platform: TargetPlatform.linux,
        phase: LedgerSigningModalPhase.readyToRetry,
        pairingCode: '123456',
      ),
    );
    await tester.pump();
    expect(find.textContaining('123456'), findsNothing);
  });

  testWidgets('the app card and status card follow the request', (
    tester,
  ) async {
    Future<void> expectCards(
      Widget harness, {
      required String app,
      required String appHint,
      required String status,
      String? badge,
    }) async {
      await tester.pumpWidget(harness);
      await tester.pump();
      expect(
        find.byKey(ValueKey('ledger_signing_step_app_$app')),
        findsOneWidget,
        reason: 'app step should be $app',
      );
      expect(find.text(appHint), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ledger_signing_status')),
          matching: find.text(status),
        ),
        findsOneWidget,
        reason: 'status card should say $status',
      );
      if (badge != null) expect(find.text(badge), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }

    await expectCards(
      _harness(phase: LedgerSigningModalPhase.connecting),
      app: 'active',
      appHint: 'Connecting to your Ledger',
      status: 'Connecting',
    );
    await expectCards(
      _harness(
        phase: LedgerSigningModalPhase.awaitingDevice,
        readiness: const LedgerAppReadinessState.inProgress(
          LedgerAppReadinessPhase.confirmOpening,
        ),
      ),
      app: 'active',
      appHint: 'Confirm on your Ledger',
      status: 'Waiting for you on Ledger',
    );
    await expectCards(
      _harness(
        phase: LedgerSigningModalPhase.awaitingDevice,
        readiness: const LedgerAppReadinessState.ready('3.9.3'),
        roundNumber: 1,
        roundCount: 2,
      ),
      app: 'done',
      appHint: 'Open on your Ledger',
      status: 'Waiting for your approval',
      badge: '1 of 2',
    );
    await expectCards(
      _harness(phase: LedgerSigningModalPhase.broadcasting, onCancel: null),
      app: 'done',
      appHint: 'Open on your Ledger',
      status: 'Broadcasting to the network',
    );
    await expectCards(
      _harness(
        phase: LedgerSigningModalPhase.failed,
        failure: const LedgerSigningFailurePresentation(
          title: 'Ledger signing failed',
          statusLabel: 'Signature not received',
          message: 'Check your Ledger, then try signing again.',
          actionLabel: 'Try again',
        ),
      ),
      app: 'done',
      appHint: 'Open on your Ledger',
      status: 'Signature not received',
    );
    await expectCards(
      _harness(
        phase: LedgerSigningModalPhase.failed,
        failure: const LedgerSigningFailurePresentation(
          title: 'Let’s reconnect your Ledger',
          statusLabel: 'Connection needed',
          message: 'Reconnect first.',
          actionLabel: 'Reconnect',
          requiresReconnect: true,
        ),
        account: const AccountInfo(
          uuid: 'ledger-1',
          name: 'Ledger',
          order: 0,
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
        ),
      ),
      app: 'failed',
      appHint: 'Reconnect your Ledger',
      status: 'Connection needed',
    );
    await expectCards(
      _harness(
        platform: TargetPlatform.linux,
        phase: LedgerSigningModalPhase.awaitingDevice,
        readiness: const LedgerAppReadinessState.ready('3.9.3'),
        pairingCode: '123456',
      ),
      app: 'active',
      appHint: 'Confirm the pairing code',
      status: 'Pairing code',
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
  TargetPlatform platform = TargetPlatform.macOS,
  bool pageLayout = false,
  required LedgerSigningModalPhase phase,
  LedgerSigningFailurePresentation? failure,
  LedgerAppReadinessState readiness = const LedgerAppReadinessState.idle(),
  VoidCallback? onFailureAction,
  VoidCallback? onCancel = _noop,
  AccountInfo? account,
  Future<void> Function(String)? reconnect,
  String? pairingCode,
  List<bool>? pairingAnswers,
  int roundNumber = 1,
  int roundCount = 1,
}) {
  return ProviderScope(
    key: ValueKey(readiness.phase),
    overrides: [
      if (reconnect != null)
        ledgerReconnectProvider.overrideWithValue(reconnect),
      if (pairingCode != null)
        ledgerPairingCodeProvider.overrideWith(
          (_) => Stream.value(pairingCode),
        ),
      if (pairingAnswers != null)
        ledgerPairingAnswerProvider.overrideWithValue(
          ({required accept}) async => pairingAnswers.add(accept),
        ),
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
          child: Builder(
            builder: (_) {
              final modal = LedgerSigningModal(
                pageLayout: pageLayout,
                phase: phase,
                failure: failure,
                onCancel: onCancel,
                onFailureAction: onFailureAction,
                accountUuid: account?.uuid,
                roundNumber: roundNumber,
                roundCount: roundCount,
              );
              return pageLayout
                  ? MobileLedgerSigningSurface(
                      onBack: _noop,
                      canLeave: true,
                      child: modal,
                    )
                  : Center(child: modal);
            },
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
