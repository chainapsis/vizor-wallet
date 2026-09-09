import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_device_illustration.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

void main() {
  testWidgets(
    'Ledger approval keeps one hierarchy and delegates cancellation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var cancellations = 0;
      await tester.pumpWidget(_harness(onCancel: () => cancellations++));

      expect(find.text('Approve voting delegation'), findsOneWidget);
      expect(find.text('Approval 2 of 3'), findsOneWidget);
      expect(find.text('Waiting for your approval'), findsOneWidget);
      expect(find.text('Delegation details'), findsOneWidget);
      expect(find.text('Voting with'), findsOneWidget);
      expect(find.text('Voting savings'), findsOneWidget);
      expect(find.text('Travel Ledger'), findsOneWidget);
      expect(find.textContaining('Account index'), findsNothing);
      expect(find.textContaining('may not display'), findsOneWidget);
      expect(find.byType(LedgerDeviceIllustration), findsOneWidget);
      expect(find.text('Submitting votes'), findsNothing);
      expect(find.text('Signing with Ledger'), findsNothing);
      expect(find.text('Signing with Keystone'), findsNothing);
      expect(find.text('Delegating voting authority'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(cancellations, 0);
      await tester.tap(find.byKey(const ValueKey('ledger_voting_cancel')));
      expect(cancellations, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('readiness transitions preserve guidance and cancel positions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_TestAccountNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _app()),
    );
    final cancel = find.byKey(const ValueKey('ledger_voting_cancel'));
    final progress = find.byKey(
      const ValueKey('ledger_voting_bundle_progress'),
    );
    final cancelRect = tester.getRect(cancel);
    final progressRect = tester.getRect(progress);
    for (final state in const [
      LedgerAppReadinessState.inProgress(
        LedgerAppReadinessPhase.checkingDevice,
      ),
      LedgerAppReadinessState.inProgress(
        LedgerAppReadinessPhase.confirmOpening,
      ),
      LedgerAppReadinessState.ready('3.9.3'),
    ]) {
      container.read(ledgerAppReadinessStateProvider.notifier).update(state);
      await tester.pump();
      expect(tester.getRect(cancel), cancelRect);
      expect(tester.getRect(progress), progressRect);
      expect(tester.takeException(), isNull);
    }
    container
        .read(ledgerAppReadinessStateProvider.notifier)
        .update(
          const LedgerAppReadinessState.failed(
            failure: LedgerAppReadinessFailure.disconnected,
            message: 'Reconnect your Ledger and try again.',
          ),
        );
    await tester.pump();
    expect(find.text('Ledger needs attention'), findsOneWidget);
    final statusIcons = tester.widgetList<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('ledger_voting_waiting_status')),
        matching: find.byType(AppIcon),
      ),
    );
    expect(statusIcons.single.name, AppIcons.warningCircle);
    expect(statusIcons.single.animated, isFalse);
  });

  testWidgets('narrow RTL and large text keep the memo and cancel reachable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var cancellations = 0;
    await tester.pumpWidget(
      _harness(
        onCancel: () => cancellations++,
        textScaler: const TextScaler.linear(2),
        direction: TextDirection.rtl,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('may not display'), findsOneWidget);
    final cancel = find.byKey(const ValueKey('ledger_voting_cancel'));
    final cancelBounds = tester.getRect(cancel);
    expect(cancel.hitTestable(), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -220),
    );
    await tester.pump();
    expect(tester.getRect(cancel), cancelBounds);
    await tester.ensureVisible(cancel);
    await tester.pump();
    await tester.tap(cancel);
    expect(cancellations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account, device and memo keep one reading order at each width', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [900.0, 393.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(_harness());
      await tester.pump();
      final device = tester.getRect(
        find.byKey(const ValueKey('ledger_voting_device_guidance')),
      );
      final memo = tester.getRect(
        find.byKey(const ValueKey('ledger_voting_delegation_details')),
      );
      final identity = tester.getRect(
        find.byKey(const ValueKey('ledger_voting_account_identity')),
      );
      expect(identity.bottom, lessThan(device.top));
      expect(device.bottom, lessThan(memo.top));
      expect(device.center.dx, closeTo(memo.center.dx, 1));
      expect(
        find.byKey(const ValueKey('ledger_voting_cancel')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('testnet uses the shared Zcash device app guidance', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        rpcEndpointProvider.overrideWith(_TestnetEndpoint.new),
        accountProvider.overrideWith(_TestAccountNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(ledgerAppReadinessStateProvider.notifier)
        .update(
          const LedgerAppReadinessState.inProgress(
            LedgerAppReadinessPhase.confirmOpening,
          ),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _app()),
    );
    expect(find.text('Open the Zcash app on your Ledger.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('post-approval Ledger and software submission retain step rows', (
    tester,
  ) async {
    for (final ledger in [true, false]) {
      await tester.pumpWidget(
        ProviderScope(
          child: _app(phase: VotingSessionPhase.delegating, ledger: ledger),
        ),
      );
      expect(find.text('Submitting votes'), findsOneWidget);
      expect(find.text('Delegating voting authority'), findsOneWidget);
      expect(find.text('Casting votes and submitting shares'), findsOneWidget);
      expect(find.text('Finalizing submission'), findsOneWidget);
      expect(find.byType(LedgerVotingSigningPanel), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'voting identity follows the signing account, not the active account',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_TestAccountNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _app()),
      );
      expect(find.text('Voting savings'), findsOneWidget);
      expect(find.text('Everyday account'), findsNothing);
      container.read(accountProvider.notifier).state = const AsyncData(
        AccountState(
          accounts: [_signingAccount, _otherAccount],
          activeAccountUuid: 'voting-ledger',
        ),
      );
      await tester.pump();
      expect(find.text('Voting savings'), findsOneWidget);
      expect(find.text('Everyday account'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing signing account never falls back to the active account',
    (tester) async {
      await tester.pumpWidget(_harness(accountUuid: 'removed-account'));
      expect(
        find.byKey(const ValueKey('ledger_voting_account_identity')),
        findsNothing,
      );
      expect(find.text('Everyday account'), findsNothing);
      expect(find.text('Approval 2 of 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long signing account and group names wrap at 200 percent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_TestAccountNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    container.read(accountProvider);
    container.read(accountProvider.notifier).state = AsyncData(
      AccountState(
        accounts: [
          _signingAccount.copyWith(
            name: 'My long-term community voting savings account',
            ledgerWalletName: 'My family Ledger wallet with a long group name',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          textScaler: const TextScaler.linear(2),
          direction: TextDirection.rtl,
        ),
      ),
    );
    expect(
      find.text('My long-term community voting savings account'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger_voting_cancel')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

const _signingAccount = AccountInfo(
  uuid: 'voting-ledger',
  name: 'Voting savings',
  order: 0,
  isHardware: true,
  hardwareSignerKind: HardwareSignerKind.ledger,
  ledgerWalletName: 'Travel Ledger',
  zip32AccountIndex: 2,
);
const _otherAccount = AccountInfo(
  uuid: 'other-ledger',
  name: 'Everyday account',
  order: 1,
  isHardware: true,
  hardwareSignerKind: HardwareSignerKind.ledger,
);

class _TestAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [_signingAccount, _otherAccount],
    activeAccountUuid: 'other-ledger',
  );
}

class _TestnetEndpoint extends RpcEndpointNotifier {
  @override
  RpcEndpointConfig build() => defaultRpcEndpointConfig('testnet');
}

Widget _harness({
  VoidCallback? onCancel,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
  String accountUuid = 'voting-ledger',
}) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    accountProvider.overrideWith(_TestAccountNotifier.new),
  ],
  child: _app(
    onCancel: onCancel,
    textScaler: textScaler,
    direction: direction,
    accountUuid: accountUuid,
  ),
);

Widget _app({
  VoidCallback? onCancel,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
  VotingSessionPhase phase = VotingSessionPhase.ledgerSigning,
  bool ledger = true,
  String accountUuid = 'voting-ledger',
}) => MaterialApp(
  home: AppTheme(
    data: AppThemeData.light,
    child: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: VotingStatusContent(
              phase: phase,
              horizontalPadding: AppSpacing.sm,
              isHardwareAccount: ledger,
              isLedgerAccount: ledger,
              ledgerAccountUuid: accountUuid,
              submissionJobInFlight: true,
              ledgerSigningBundleIndex: 1,
              ledgerSigningBundleCount: 3,
              ledgerDisplayMemo:
                  'Round 7\nAmount: 0.25 ZEC\nDelegate voting authority',
              onCancelLedger: onCancel,
            ),
          ),
        ),
      ),
    ),
  ),
);
